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
    /// For a run repeated with `-test-iterations`: each repeated test, and how many of its runs failed.
    public var repeated: [ResultBundle.Repeated]?

    /// The warnings in lines the branch changed, a few named; nothing when there are none.
    static func warningsNote(_ inChanged: [ToolOutput.Warning], of total: Int) -> String? {
        guard !inChanged.isEmpty else { return nil }
        // Messages carry commas, so a semicolon parts them.
        let named = inChanged.map { "\(ToolOutput.basename($0.path ?? "")):\($0.line ?? 0) \($0.message)" }
        return "xcrew: \(inChanged.count) of \(total) warnings are in lines this branch changed\(ResultBundle.listed(named, separator: "; "))."
    }

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
    public static func make(kind: Kind, output: ToolOutput, home: String, runner: any CommandRunning, repeated: Bool = false, project: Project? = nil, machine: Machine? = nil) async -> Report {
        let saved = savedPath(output.text)
        let read = saved.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }.map { ToolOutput(text: $0, server: output.server, isError: output.isError) } ?? output
        let isTest = kind == .test
        // MobileBuildMCP's text omits what its result bundle knows; the Xcode MCP's results carry their own.
        let bundle = isTest ? ResultBundle.path(in: read, home: home).map { ResultBundle(path: $0, runner: runner) } : nil
        // The summary is needed whatever the run came to, so it's asked for while the failures are looked up.
        async let bundleSummary: String? = { await bundle?.summary() }()
        // What the branch changed is listed once, by whichever asks first, meanwhile: for the warnings that name a
        // place, and for a test run with coverage.
        let warnings = read.warnings
        let warned = warnings.compactMap(\.path)
        let change = Once { () async -> GitChanges.Change? in
            guard let project, case let .success(change) = await GitChanges.since(nil, in: project, using: runner) else { return nil }
            return change
        }
        async let changed: [String: [ClosedRange<Int>]]? = {
            guard let project, !warned.isEmpty, let listed = await change.value() else { return nil }
            return await ChangedLines.of(warned, in: listed, project: project, using: runner)
        }()
        async let coverage: ChangedLineCoverage? = {
            guard let project, let bundle else { return nil }
            return await ChangedLineCoverage.within(ChangedLineCoverage.budget) {
                let covered = await bundle.coveredFiles()
                guard !covered.isEmpty, let listed = await change.value() else { return nil }
                return await ChangedLineCoverage.of(covered, in: listed, bundle: bundle, project: project, using: runner)
            }
        }()
        async let why: String? = {
            guard let project, !read.summary.ok else { return nil }
            return await Why.note(for: read, home: home, project: project, runner: runner)
        }()
        async let pinNote: String? = {
            // MobileBuildMCP builds with the Xcode the pin decides; the Xcode MCP, with whichever is open.
            guard read.server == .mobileBuildMCP, let project, let machine, !read.summary.ok else { return nil }
            return XcodePinCheck.failureNote(await XcodeSnapshot.take(of: project, on: machine), hasXcodes: machine.runner.which("xcodes") != nil)
        }()
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
        // A run repeated with `-test-iterations` says, per test, whether it's flaky or failing for real.
        var repeatedTests: [ResultBundle.Repeated]?
        if repeated {
            let found = if let bundle { ResultBundle.repetitions(listing: await bundle.tests()) } else { [ResultBundle.Repeated]() }
            notes.append(ResultBundle.repetitionsNote(found) ?? ResultBundle.noRepetitionsNote)
            repeatedTests = found
        }

        // The warnings in lines this branch changed, named: those are Claude's to fix. Nothing is said about the rest, or
        // about warnings the change causes in lines it left alone.
        if let changed = await changed {
            let inChanged = warnings.filter { warning in
                guard let path = warning.path, let line = warning.line else { return false }
                return changed[path]?.contains { $0.contains(line) } == true
            }
            if let note = warningsNote(inChanged, of: warnings.count) { notes.append(note) }
        }

        if let note = await coverage?.note { notes.append(note) }

        // A run that failed because of the Mac says so first: its errors would read as the code's.
        if let why = await why { notes.insert(why, at: 0) }
        if let pinNote = await pinNote { notes.append(pinNote) }

        let compact = saved.flatMap { final.compactTestResult(savedPath: $0) } ?? (saved == nil ? final.compactTestText : nil)
        return Report(
            ok: summary.ok,
            detail: summary.detail,
            durationMs: final.reportedDuration,
            tests: tests,
            failures: summary.ok ? [] : final.failures,
            result: compact ?? (edited ? final.text : nil),
            notes: notes,
            repeated: repeatedTests
        )
    }
}
