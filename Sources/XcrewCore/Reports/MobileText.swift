import Foundation

/// MobileBuildMCP's text, which it returns instead of JSON when a build or test run fails, read
/// once into lines that each know their shape. Annotating and compacting edit these lines; `text`
/// writes them back out unchanged where nothing edited them.
struct MobileText: Sendable {
    /// A `✗` entry: a failing test, or a compile error.
    struct Entry: Sendable {
        let text: String
        /// The test and its message, when the entry is a failing test's.
        let failing: (test: TestID, message: String)?

        var isExcerpt: Bool { MobileBuildMCPLine.isExcerpt(text) }
    }

    enum Kind: Sendable {
        case entry(Entry)
        case location(path: String, line: String)
        /// `⚠ <message>`, a compiler warning, with the spaces before it.
        case warning(indent: String, message: String)
        case heading(MobileBuildMCPLine.Heading)
        /// A skipped test's line, naming the test when it has the usual shape.
        case skipped(TestID?)
        /// The `skipped: <reason>` line Xcrew adds under a skipped test.
        case skipReason
        case passed
        case summary
        case other
    }

    struct Line: Sendable {
        let text: String
        let kind: Kind

        init(_ text: String) {
            self.text = text
            if let entry = MobileBuildMCPLine.entry(text) {
                kind = .entry(Entry(text: entry, failing: MobileBuildMCPLine.test(in: entry)))
            } else if let location = MobileBuildMCPLine.location(text) {
                kind = .location(path: location.path, line: location.line)
            } else if let heading = MobileBuildMCPLine.heading(text) {
                kind = .heading(heading)
            } else if MobileBuildMCPLine.isSummary(text) {
                kind = .summary
            } else if MobileBuildMCPLine.isSkipped(text) {
                kind = .skipped(MobileBuildMCPLine.skipped(text))
            } else if MobileBuildMCPLine.isSkipReason(text) {
                kind = .skipReason
            } else if MobileBuildMCPLine.isPassed(text) {
                kind = .passed
            } else if let warning = MobileBuildMCPLine.warning(text) {
                kind = .warning(indent: warning.indent, message: warning.message)
            } else {
                kind = .other
            }
        }

        var entry: Entry? {
            if case let .entry(entry) = kind { return entry }
            return nil
        }

        var failing: (test: TestID, message: String)? { entry?.failing }

        var location: (path: String, line: String)? {
            if case let .location(path, line) = kind { return (path, line) }
            return nil
        }

        var warning: (indent: String, message: String)? {
            if case let .warning(indent, message) = kind { return (indent, message) }
            return nil
        }

        var isSummary: Bool {
            if case .summary = kind { return true }
            return false
        }

        var isPassed: Bool {
            if case .passed = kind { return true }
            return false
        }

        func isHeading(_ heading: MobileBuildMCPLine.Heading) -> Bool {
            if case .heading(heading) = kind { return true }
            return false
        }

        var isBlank: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var lines: [Line]

    init(_ text: String) {
        lines = text.components(separatedBy: "\n").map(Line.init)
    }

    init(lines: [Line]) {
        self.lines = lines
    }

    var text: String { lines.map(\.text).joined(separator: "\n") }

    /// A test run's text, as opposed to a build's.
    var isTestRun: Bool { lines.first.map { MobileBuildMCPLine.isTestRunHeader($0.text) } == true }

    /// The location on the line after `index`, if that line is one.
    func location(after index: Int) -> (path: String, line: String)? {
        index + 1 < lines.count ? lines[index + 1].location : nil
    }

    /// Each compiler warning, once for each place it fires, with that place when the next line gives one.
    var warnings: [RepeatedWarnings.Warning] {
        lines.indices.compactMap { index in
            lines[index].warning.map { RepeatedWarnings.Warning(message: $0.message, location: location(after: index).map { RepeatedWarnings.Location(path: $0.path, line: $0.line) }) }
        }
    }

    // MARK: Reading

    /// A failing run's counts, from its summary line.
    var counts: TestCounts? {
        lines.lazy.filter(\.isSummary).compactMap { MobileBuildMCPLine.counts(in: $0.text) }.first
    }

    /// How many tests the summary line, passing or failing, counts as skipped.
    var skippedCount: Int {
        lines.lazy.filter(\.isSummary).compactMap { MobileBuildMCPLine.skippedCount(in: $0.text) }.first ?? 0
    }

    /// The run's `(⏱️ 12.3s)`, in milliseconds.
    var durationMs: Int? {
        lines.lazy.compactMap { MobileBuildMCPLine.duration(in: $0.text) }.first.map(ToolOutput.milliseconds)
    }

    /// The `.xcresult` path the text lists: the workspace folder, then the bundle under it.
    var resultBundle: String? {
        guard let folder = workspaceFolder, let bundle = lines.lazy.compactMap({ MobileBuildMCPLine.resultBundle($0.text) }).first else { return nil }
        return folder + bundle
    }

    /// The run's workspace folder, which the artifacts the text lists below it are under.
    var workspaceFolder: String? {
        lines.lazy.compactMap { MobileBuildMCPLine.workspaceFolder($0.text) }.first
    }

    /// The build log the text lists: by itself, or under the workspace folder.
    var buildLog: String? {
        guard let log = lines.lazy.compactMap({ MobileBuildMCPLine.buildLog($0.text) }).first else { return nil }
        if log.hasPrefix("/") || log.hasPrefix("~") { return log }
        return workspaceFolder.map { $0 + log }
    }

    /// Each error, with the file it names and the lines that go on from it. A failing test's starts with its name.
    var reportedErrors: [ReportedError] {
        lines.indices.compactMap { index in
            guard let entry = lines[index].entry, !entry.isExcerpt else { return nil }
            let location = location(after: index)
            var detail: [String] = []
            var next = index + (location == nil ? 1 : 2)
            while next < lines.count, case .other = lines[next].kind, !lines[next].isBlank {
                detail.append(lines[next].text.trimmingCharacters(in: .whitespaces))
                next += 1
            }
            return ReportedError(message: entry.text, detail: detail, path: location?.path, line: location.flatMap { Int($0.line.prefix { $0.isNumber }) })
        }
    }

    var summary: ToolOutput.Summary? {
        if let counts {
            let first = lines.lazy.compactMap(\.failing).first
            return ToolOutput.Summary(ok: false, detail: "\(counts.failed ?? 0) of \(counts.sum) failed\(first.map { " · \($0.test.shown)" } ?? "")")
        }
        if isTestRun, lines.contains(where: { MobileBuildMCPLine.isTestRunFailure($0.text) }) { return ToolOutput.Summary(ok: false, detail: ToolOutput.testsDidNotRun) }
        if lines.contains(where: { MobileBuildMCPLine.isBuildFailure($0.text) }) {
            // The first error MobileBuildMCP gives a location for.
            let first = lines.indices.lazy.compactMap { index in
                lines[index].entry.flatMap { entry in location(after: index).map { (entry, $0) } }
            }.first
            guard let (entry, location) = first else { return ToolOutput.Summary(ok: false) }
            return ToolOutput.Summary(ok: false, detail: "\(ToolOutput.basename(location.path)):\(location.line) \(entry.text)")
        }
        return nil
    }

    /// `✗ Suite / test: message` or `✗ message`, each maybe followed by its `/path:line`.
    var failures: [ToolOutput.Failure] {
        var failures: [ToolOutput.Failure] = []
        var seen: Set<TestID> = []
        for (index, line) in lines.enumerated() {
            guard let entry = line.entry, !entry.isExcerpt else { continue }
            let location = location(after: index).map { "\(ToolOutput.basename($0.path)):\($0.line)" }
            if let failing = entry.failing {
                // It lists a failing test twice, once with its location; the first is kept.
                guard seen.insert(failing.test).inserted else { continue }
                // XCTest words an XCTFail as `failed - <message>`; the message is what was written.
                let message = failing.message.replacing(#/^failed - /#, with: "")
                failures.append(ToolOutput.Failure(title: failing.test.shown, message: message, where: location, isTest: true))
            } else if let location {
                failures.append(ToolOutput.Failure(title: location, message: entry.text))
            } else if let split = entry.text.range(of: ": "), split.lowerBound > entry.text.startIndex {
                failures.append(ToolOutput.Failure(title: String(entry.text[..<split.lowerBound]), message: String(entry.text[split.upperBound...])))
            } else {
                failures.append(ToolOutput.Failure(title: entry.text, message: ""))
            }
        }
        return failures
    }

    // MARK: Editing

    /// Passing tests listed past this many are counted instead: a failing run's list is what pushes it over the limit.
    static let passingListLimit = 20

    /// With `showTestTiming` on, a failing test run lists every passing test under `Test Results:`.
    /// This keeps the failures, the failing and skipped tests' lines and the summary, and counts the
    /// passing ones. Nil when the list is short or the text is another shape.
    func compacted() -> MobileText? {
        guard lines.first.map({ MobileBuildMCPLine.isTestHeader($0.text) }) == true, let start = lines.firstIndex(where: { $0.isHeading(.testResults) }) else { return nil }
        // The list runs to the summary line; a blank line inside it is where Claude Code cut a long one.
        let summary = lines.indices.first { $0 > start && lines[$0].isSummary }
        var end = summary ?? start + 1
        if summary == nil { while end < lines.count, !lines[end].isBlank { end += 1 } }
        while end > start + 1, lines[end - 1].isBlank { end -= 1 }
        let section = lines[(start + 1)..<end]
        let listed = section.filter(\.isPassed).count
        guard listed > Self.passingListLimit else { return nil }
        // The summary's count, since Claude Code may already have cut the middle of a long list.
        let passed = counts?.passed ?? listed
        // Failing tests are listed in full under Test Failures, while this list's ❌ lines come from the
        // parallel runners' log and can miss some, so only skipped tests (⏭️) keep their lines here.
        let listedAbove = lines.contains { $0.isHeading(.testFailures) }
        let kept = section.filter { line in
            switch line.kind {
            case .skipped, .skipReason: true
            default: !listedAbove && MobileBuildMCPLine.isFailed(line.text)
            }
        }
        let note = listedAbove ? "  (\(passed) passing tests left out; failing tests are listed in full above)" : "  (\(passed) passing tests left out)"
        return MobileText(lines: Array(lines[...start]) + [Line(note)] + kept + Array(lines[end...]))
    }

    /// MobileBuildMCP lists a compile error twice: the message, and the compiler's caret line
    /// (`✗ |   \`- error: …`) as an error of its own. This drops the caret line and corrects the count.
    func withoutExcerpts() -> MobileText? {
        var kept: [Line] = []
        var dropped = 0
        for line in lines {
            if line.entry?.isExcerpt == true {
                dropped += 1
                if kept.last?.isBlank == true { kept.removeLast() }
                continue
            }
            kept.append(line)
        }
        guard dropped > 0 else { return nil }
        if let index = kept.firstIndex(where: { $0.isHeading(.errors) }), let header = MobileBuildMCPLine.errorCount(in: kept[index].text) {
            kept[index] = Line(kept[index].text.replacingCharacters(in: header.range, with: "Errors (\(max(1, header.count - dropped))):"))
        }
        return MobileText(lines: kept)
    }

    /// A warning that fires in several places is listed once for each, its message and then its
    /// location; this lists it once, with how many times and every place, where it was first listed.
    func collapsingWarnings() -> MobileText? {
        guard let groups = RepeatedWarnings.grouped(warnings) else { return nil }
        let repeated = Dictionary(uniqueKeysWithValues: groups.filter { $0.count > 1 }.map { ($0.message, $0) })
        var listed: Set<String> = []
        var kept: [Line] = []
        var placeOfDropped: Int?
        for (index, line) in lines.enumerated() where index != placeOfDropped {
            guard let warning = line.warning, let group = repeated[warning.message] else {
                kept.append(line)
                continue
            }
            placeOfDropped = location(after: index) != nil ? index + 1 : nil
            if listed.insert(warning.message).inserted {
                kept.append(Line(warning.indent + "⚠ " + RepeatedWarnings.line(group)))
            } else if kept.last?.isBlank == true {
                kept.removeLast()
            }
        }
        return MobileText(lines: kept)
    }
}
