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

    /// The longest text read as a notice: far below the size at which Claude Code saves a result (docs/findings.md),
    /// with room for the saved JSON's schema the notice names.
    static let noticeLimit = 10_000

    /// The file Claude Code saved a result to, from the notice it left in the result's place. Found by the file, not the
    /// notice's wording, which is undocumented: a file directly in a `tool-results` folder below a `projects` folder,
    /// where the docs say it saves one, that exists. The config folder above isn't checked, since `CLAUDE_CONFIG_DIR`
    /// moves it. A path runs to the next space; whatever closes it (`.`, a quote, a bracket) is trimmed until a file is found.
    static func savedPath(_ text: String) -> String? {
        guard text.utf8.count <= noticeLimit else { return nil }
        for match in text.matches(of: #/\/\S*\/projects\/\S+\/tool-results\/[^\s\/]+/#) {
            var path = Substring(match.output)
            while let last = path.last {
                if isFile(path) { return String(path) }
                guard !last.isLetter, !last.isNumber else { break }
                path.removeLast()
            }
        }
        return nil
    }

    static func isFile(_ path: some StringProtocol) -> Bool {
        (try? URL(fileURLWithPath: String(path)).resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }

    /// A result Claude Code saved to a file is read back from it.
    public static func make(kind: Kind, output: ToolOutput, home: String, runner: any CommandRunning) async -> Report {
        let saved = savedPath(output.text)
        let read = saved.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }.map { ToolOutput(text: $0, server: output.server, isError: output.isError) } ?? output
        let isTest = kind == .test
        // MobileBuildMCP's text omits what its result bundle knows; the Xcode MCP's results carry their own.
        let bundle = isTest ? ResultBundle.path(in: read, home: home).map { ResultBundle(path: $0, runner: runner) } : nil
        // The summary is needed whatever the run came to, so it's asked for while the failures are looked up.
        async let bundleSummary: String? = { await bundle?.summary() }()
        var final = read
        var edited = false
        // A saved result stays saved unless it's compacted below: Claude Code saved it for its size, which the collapse alone may not cut enough.
        if let collapsed = read.collapsingWarnings() { (final, edited) = (collapsed, saved == nil) }
        if let text = final.mobileText {
            if let bundle, text.isTestRun {
                if let annotated = await FailureNotes.adding(to: text, from: bundle) { (final, edited) = (ToolOutput(annotated, isError: output.isError), true) }
            } else if let cleaned = text.withoutExcerpts() {
                (final, edited) = (ToolOutput(cleaned, isError: output.isError), true)
            }
        }
        let summary = final.summary

        var notes: [String] = []
        let tests = final.testTotal
        if isTest, tests == 0 { notes.append(noTestsNote) }
        if let bundle, let summary = await bundleSummary {
            // The test list is only asked for when the summary counts expected failures to name.
            let names = ResultBundle.expectedFailureCount(summary: summary) > 0 ? ResultBundle.expectedFailures(listing: await bundle.tests()) : []
            if let expected = ResultBundle.expectedFailuresNote(summary: summary, names: names) { notes.append(expected) }
        }

        let compact = saved.flatMap { final.compactTestResult(savedPath: $0) } ?? (saved == nil ? final.compactTestText : nil)
        return Report(
            ok: summary.ok,
            detail: summary.detail,
            durationMs: final.reportedDuration,
            tests: tests,
            failures: summary.ok ? [] : final.failures,
            result: compact ?? (edited ? final.text : nil),
            notes: notes
        )
    }
}
