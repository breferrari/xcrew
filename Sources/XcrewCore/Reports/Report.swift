import Foundation

/// Everything the mod shows and hands on for one finished build, test or run call, worked out from
/// the server's output: the outcome for the band, the failures for the pane, the duration and test
/// count for the history, and the shorter result and notes Claude reads.
public struct Report: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable { case build, test, run }

    public var ok: Bool
    public var detail: String?
    /// How long the server says the run took; nil when it doesn't say.
    public var durationMs: Int?
    /// How many tests ran, for the next run's `testing 312 of 959`.
    public var tests: Int?
    public var failures: [ToolOutput.Failure]
    /// What Claude reads in place of the server's result; nil keeps the server's.
    public var result: String?
    /// Lines added beside the result for Claude.
    public var notes: [String]

    static let noTestsNote =
        "xcrew: this test run ran no tests (passed, failed and skipped are all 0), though it reports SUCCEEDED. An -only-testing or -skip-testing filter that matches nothing does this; check the target and class names."

    /// Claude Code's notice for a result over its size limit, naming the file that holds the whole text.
    static func savedPath(_ text: String) -> String? {
        text.firstMatch(of: #/Output has been saved to (\/\S+\/tool-results\/\S+?)\.\s/#).map { String($0.1) }
    }

    /// `server` is `MobileBuildMCP` or `xcode`. A result Claude Code saved to a file is read back from it.
    public static func make(server: String, kind: Kind, output: ToolOutput, home: String, runner: any CommandRunning) async -> Report {
        let saved = savedPath(output.text)
        let read = saved.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? output.text
        // MobileBuildMCP's text omits what its result bundle knows; the Xcode MCP's results carry their own.
        let isMobile = server == "MobileBuildMCP"
        let isTest = kind == .test
        let bundle = isMobile && isTest ? ResultBundle.path(in: read, home: home).map { ResultBundle(path: $0, runner: runner) } : nil
        let located = read.hasPrefix("🧪") ? await bundle.asyncMap { await FailureNotes.adding(to: read, from: $0) } : nil
        let text = located ?? (isMobile ? ToolOutput(text: read).cleanBuildText : nil) ?? read
        let final = ToolOutput(text: text, isError: output.isError)
        let summary = final.summary

        var notes: [String] = []
        if isTest, final.testTotal == 0 { notes.append(noTestsNote) }
        if let bundle, let expected = ResultBundle.expectedFailuresNote(summary: await bundle.summary()) { notes.append(expected) }

        let compact = saved.flatMap { final.compactTestResult(savedPath: $0) } ?? (saved == nil ? final.compactTestText : nil)
        return Report(
            ok: summary.ok,
            detail: summary.detail,
            durationMs: final.reportedDuration,
            tests: final.testTotal,
            failures: summary.ok ? [] : final.failures,
            result: compact ?? (text != read ? text : nil),
            notes: notes
        )
    }
}

extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async -> T) async -> T? {
        guard let self else { return nil }
        return await transform(self)
    }
}
