import Foundation

/// A pull request's evidence from what xcrew knows of its branch: a Markdown block safe to paste into the PR, and apart
/// from it, the local images for the person to attach. The block never holds a path of this Mac or an id of its devices.
public enum EvidencePack {
    /// The block to paste, and the images to attach, which never go inside it.
    public struct Text: Sendable, Equatable {
        public let block: String
        public let attach: String?
    }

    /// Tests listed in each part; the rest are counted.
    static let mostTests = 10

    /// The pack for the ledger and times the mod holds, with each red-to-green test's images read again from its failing
    /// run's result bundle, which `bundle` opens. Nil when there's nothing to say.
    public static func make(_ input: EvidenceInput, project: Project, machine: Machine, bundle: (@Sendable (String) -> ResultBundle)? = nil) async -> Text? {
        let open = bundle ?? { ResultBundle(path: $0, runner: machine.runner) }
        let images = machine.cacheFolder.appending(path: "images")
        var parts: [[String]] = []
        var attach: [String] = []

        let greened = input.ledger.filter { $0.green != nil }
        if !greened.isEmpty {
            var lines = ["Tests this branch took from red to green:"]
            for entry in greened.prefix(mostTests) {
                guard let green = entry.green else { continue }
                let message = entry.red.message.map { " (\(quoted($0)))" } ?? ""
                var line = "- `\(entry.test)`: failed in `\(entry.red.scope)`\(message), then passed in `\(green.scope)`."
                if let path = entry.red.bundle {
                    if FileManager.default.fileExists(atPath: path) {
                        let found = await kept(of: TestID(xcresultID: entry.test), in: open(path), keptIn: images)
                        if let found {
                            line += " \(found.label): attached below."
                            attach += ["- `\(entry.test)`, \(found.label.lowercased()):"] + found.paths.map { "  \($0)" }
                        }
                    } else {
                        line += " Its failing run's result bundle is gone, and its images with it."
                    }
                } else {
                    line += " Its images aren't known: its failing run was recorded before xcrew kept the run's result bundle."
                }
                lines.append(line)
            }
            lines += more(greened.count)
            parts.append(lines)
        }

        let red = input.ledger.filter { $0.green == nil }
        if !red.isEmpty {
            let lines = red.prefix(mostTests).map { entry in
                "- `\(entry.test)`: " + quoted(entry.red.message ?? "failed") + (entry.flaky.map { ", flaky, failing \($0.failed) of \($0.runs) runs" } ?? "")
            }
            parts.append(["Still red:"] + lines + more(red.count))
        }

        let changed = await changedLines(project: project, machine: machine)
        if !changed.isEmpty { parts.append(["Changed lines:"] + changed) }

        if !input.times.isEmpty { parts.append(["Usual run times:"] + input.times.map { "- \($0)" }) }

        guard !parts.isEmpty else { return nil }
        let block = scrubbed((["## Evidence"] + parts.map { $0.joined(separator: "\n") }).joined(separator: "\n\n"), roots: [project.root.path, project.canonicalRoot])
        return Text(block: block, attach: attach.isEmpty ? nil : (["Images to attach (for you, not the PR):"] + attach).joined(separator: "\n"))
    }

    /// What the newest test run's coverage and the newest build's warnings say of the lines this branch changed, in
    /// this project's MobileBuildMCP workspace, each dated by its run and said to be older than the last commit when it is.
    static func changedLines(project: Project, machine: Machine) async -> [String] {
        let runner = machine.runner
        guard case let .success(change) = await GitChanges.since(nil, in: project, using: runner) else { return [] }
        let committed = await runner.run(["git", "-C", project.root.path, "log", "-1", "--format=%ct"], stdin: nil, timeout: .seconds(10))
        let lastCommit = TimeInterval(committed.stdout.trimmingCharacters(in: .whitespacesAndNewlines)).map(Date.init(timeIntervalSince1970:))
        var lines: [String] = []
        if let run = RunLog.find(in: "result-bundles", since: .distantPast, project: project.root, home: machine.home, named: { $0.hasPrefix("test") && $0.hasSuffix(".xcresult") }) {
            let bundle = ResultBundle(path: run.path, runner: runner)
            let note = await ChangedLineCoverage.within(ChangedLineCoverage.budget) {
                let covered = await bundle.coveredFiles()
                return covered.isEmpty ? nil : await ChangedLineCoverage.of(covered, in: change, bundle: bundle, project: project, using: runner)
            }?.note
            if let note { lines.append("- \(when("the test run", at: modified(run), lastCommit: lastCommit)): \(unprefixed(note))") }
        }
        if let log = RunLog.newestBuild(project: project.root, home: machine.home), let text = try? String(contentsOf: log, encoding: .utf8) {
            var seen = Set<ToolOutput.Warning>()
            let warnings = text.split(separator: "\n").compactMap { line -> ToolOutput.Warning? in
                guard let match = line.wholeMatch(of: /(\/.+?):(\d+):\d+: warning: (.+)/) else { return nil }
                return ToolOutput.Warning(message: String(match.output.3), path: String(match.output.1), line: Int(match.output.2))
            }.filter { seen.insert($0).inserted }
            let ranges = await ChangedLines.of(warnings.compactMap(\.path), in: change, project: project, using: runner) ?? [:]
            let inChanged = warnings.filter { warning in warning.line.map { line in ranges[warning.path ?? ""]?.contains { $0.contains(line) } == true } ?? false }
            if let note = Report.warningsNote(inChanged, of: warnings.count) { lines.append("- \(when("the build", at: modified(log), lastCommit: lastCommit)): \(unprefixed(note))") }
        }
        return lines
    }

    static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    /// A note as Claude reads it, without its `xcrew: `.
    static func unprefixed(_ note: String) -> String {
        note.hasPrefix("xcrew: ") ? String(note.dropFirst("xcrew: ".count)) : note
    }

    /// `- +3 more`, past the tests listed.
    static func more(_ count: Int) -> [String] {
        count > mostTests ? ["- +\(count - mostTests) more"] : []
    }

    static func quoted(_ message: String) -> String {
        "\"\(message)\""
    }

    /// A failed test's images from its run: a snapshot's, as `FailureNotes` lists them, or else a UI test's screen at the
    /// failure, as `look` keeps it.
    static func kept(of test: TestID, in bundle: ResultBundle, keptIn images: URL) async -> (label: String, paths: [String])? {
        if let found = await bundle.images(of: test, keptIn: images) { return ("Images from its failing run", found.shown) }
        guard let runs = FailedRun.runs(activities: await bundle.activities(of: test)), let failed = runs.first(where: \.hasRecording) else { return nil }
        let screen = await bundle.attachments(of: test, onlyFailures: false) { export in
            await FailureScreen.keep(of: test, run: failed, files: Look.files(in: export), in: bundle.runFolder(in: images))
        }
        return screen.map { ("The screen when it failed", [$0.path]) }
    }

    /// The text with every path of this Mac made relative to the project's root, or cut to its file's name when outside
    /// it, and every UUID, a simulator's or a device's, replaced.
    static func scrubbed(_ text: String, roots: [String]) -> String {
        var text = text
        for root in Set(roots) where !root.isEmpty { text = text.replacingOccurrences(of: root + "/", with: "") }
        text = text.replacing(/\/(?:Users|private|var|tmp|Volumes|Applications|Library|System|opt)\/[^\s"'()\[\],;]+/) { match in
            String(match.output.split(separator: "/").last ?? "")
        }
        return text.replacing(/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/, with: "<id>")
    }

    /// `From the test run of 2026-10-30 14:24 UTC`, said to be older than the branch's last commit when it is.
    static func when(_ what: String, at: Date, lastCommit: Date?) -> String {
        let said = "From \(what) of \(stamp(at))"
        guard let lastCommit, at < lastCommit else { return said }
        return "\(said), older than the branch's last commit (\(stamp(lastCommit)))"
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        return formatter.string(from: date)
    }
}
