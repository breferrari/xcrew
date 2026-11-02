import Foundation

/// A pull request's evidence from what xcrew knows of its branch: a Markdown block safe to paste into the PR, and apart
/// from it, the local images for the person to attach. The block never holds a path of this Mac or an id of its devices.
public enum EvidencePack {
    /// What a red test the newest run in its scope didn't run is said to be; the mod's ledger says it in the same words.
    public static let notInNewestRun = "not in the newest run of its scope"

    /// The block to paste, and the images to attach, which never go inside it.
    public struct Text: Sendable, Equatable {
        public let block: String
        public let attach: String?
    }

    /// The block's heading, which the routing rules name.
    public static let heading = "## Evidence"

    /// Tests listed in each part; the rest are counted.
    static let mostTests = 10

    /// The pack for the ledger the mod holds, with each red-to-green test's images read again from its failing
    /// run's result bundle, which `open` opens. Nil when there's nothing to say.
    public static func make(_ input: EvidenceInput, project: Project, machine: Machine, open: @escaping @Sendable (String) -> ResultBundle) async -> Text? {
        async let changed = changedLines(project: project, machine: machine)
        let images = machine.cacheFolder.appending(path: "images")
        var parts: [[String]] = []
        var attach: [String] = []

        let greened = input.ledger.compactMap { entry in entry.green.map { (entry, $0) } }
        if !greened.isEmpty {
            let shown = Array(greened.prefix(mostTests))
            let looked = await imagesOf(shown.map(\.0), open: open, keptIn: images)
            var lines = ["Tests this branch took from red to green:"]
            for ((entry, green), found) in zip(shown, looked) {
                let message = entry.red.message.map { " (\(quoted($0)))" } ?? ""
                let flaky = entry.flaky.flatMap { flaky in flaky.needed.map { " Flaky: it failed \(flaky.failed) of \(flaky.runs) runs, then passed \(flaky.passes ?? 0) in a row in repeated runs, of \($0) needed." } } ?? ""
                lines.append("- `\(entry.test)`: failed in `\(entry.red.scope)`\(message), then passed in `\(green.scope)`.\(found.said)\(flaky)")
                if let paths = found.paths { attach += ["- `\(entry.test)`, \(found.label.lowercased()):"] + paths.map { "  \($0)" } }
            }
            parts.append(lines + more(greened.count))
        }

        let red = input.ledger.filter { $0.green == nil }
        if !red.isEmpty {
            let lines = red.prefix(mostTests).map { entry in
                "- `\(entry.test)`: " + quoted(entry.red.message ?? "failed") + (entry.flaky.map { flaky in
                    ", flaky, failing \(flaky.failed) of \(flaky.runs) runs" + (flaky.needed.map { ", passed \(flaky.passes ?? 0) of the \($0) needed \(FlakyMark.passesCountedFrom)" } ?? "")
                } ?? "") + (entry.unseen == nil ? "" : ", \(Self.notInNewestRun)")
            }
            parts.append(["Still red:"] + lines + more(red.count))
        }
        if input.ledger.contains(where: { $0.flaky?.needed != nil }) { parts.append([FlakyMark.neededMeaning]) }

        let changedLines = await changed
        if !changedLines.isEmpty { parts.append(["Changed lines:"] + changedLines) }

        guard !parts.isEmpty else { return nil }
        let block = scrubbed(([heading] + parts.map { $0.joined(separator: "\n") }).joined(separator: "\n\n"), roots: [project.root.path, project.canonicalRoot])
        return Text(block: block, attach: attach.isEmpty ? nil : (["Images to attach (for you, not the PR):"] + attach).joined(separator: "\n"))
    }

    /// What a red-to-green test's line says of its failing run's images, and their paths when there are any.
    struct Found: Sendable {
        var label = ""
        var said = ""
        var paths: [String]?
    }

    /// Each entry's images, a few entries at a time, in their order.
    static func imagesOf(_ entries: [EvidenceInput.Entry], open: @escaping @Sendable (String) -> ResultBundle, keptIn images: URL) async -> [Found] {
        await withTaskGroup(of: (Int, Found).self) { group in
            var pending = entries.enumerated().makeIterator()
            func next() {
                guard let (index, entry) = pending.next() else { return }
                group.addTask { (index, await found(for: entry, open: open, keptIn: images)) }
            }
            for _ in 0..<FailureNotes.mostAtOnce { next() }
            var results = [Found](repeating: Found(), count: entries.count)
            while let (index, one) = await group.next() {
                results[index] = one
                next()
            }
            for path in Set(entries.compactMap(\.red.bundle)) {
                let run = open(path).runFolder(in: images)
                if FileManager.default.fileExists(atPath: run.path) { FailureImages.record(run) }
            }
            return results
        }
    }

    static func found(for entry: EvidenceInput.Entry, open: (String) -> ResultBundle, keptIn images: URL) async -> Found {
        guard let path = entry.red.bundle else {
            return Found(said: " Its images aren't known: its failing run was recorded before xcrew kept the run's result bundle.")
        }
        guard FileManager.default.fileExists(atPath: path) else { return Found(said: " Its failing run's result bundle is gone, and its images with it.") }
        guard let kept = await kept(of: TestID(xcresultID: entry.test), in: open(path), keptIn: images) else { return Found() }
        return Found(label: kept.label, said: " \(kept.label): attached below.", paths: kept.paths)
    }

    /// A failed test's images from its run, from one export of its attachments: a snapshot's, as `FailureNotes` lists them,
    /// or else a UI test's screen at the failure, as `look` keeps it.
    static func kept(of test: TestID, in bundle: ResultBundle, keptIn images: URL) async -> (label: String, paths: [String])? {
        async let activities = bundle.activities(of: test)
        let run = bundle.runFolder(in: images)
        let failed = FailedRun.runs(activities: await activities)?.first(where: \.hasRecording)
        return await bundle.attachments(of: test, onlyFailures: false) { export in
            if let found = FailureImages.keep(of: test, from: export, in: run) { return ("Images from its failing run", found.shown) }
            guard let failed, let screen = await FailureScreen.keep(of: test, run: failed, files: Look.files(in: export), in: run) else { return nil }
            return ("The screen when it failed", [screen.path])
        }
    }

    /// One run's say on the changed lines: what it was, the file that dates it, and its sentence.
    typealias Said = (what: String, dated: URL, sentence: String)

    /// What the newest finished test run's coverage and the newest build's warnings say of the lines this branch changed,
    /// in this project's MobileBuildMCP workspace, each dated by its run and said to be older than the last commit when it is.
    static func changedLines(project: Project, machine: Machine) async -> [String] {
        let runner = machine.runner
        guard case let .success(change) = await GitChanges.since(nil, in: project, using: runner) else { return [] }
        async let committed = runner.run(["git", "-C", project.root.path, "log", "-1", "--format=%ct"], stdin: nil, timeout: .seconds(10))
        async let coverage: (said: Said, at: [Date], onlySinceLastCommit: Bool, leftOut: Int)? = branchCoverage(change: change, project: project, machine: machine)
        async let warnings: Said? = {
            guard let log = RunLog.newestBuild(project: project.root, home: machine.home), let text = try? String(contentsOf: log, encoding: .utf8) else { return nil }
            let found = BuildLog.warnings(in: text)
            guard let inChanged = await ChangedLines.warnings(found, in: change, project: project, using: runner),
                  let sentence = Report.warningsSentence(inChanged, of: found.count)
            else { return nil }
            return ("the build", log, sentence)
        }()
        let lastCommit = TimeInterval(await committed.stdout.trimmingCharacters(in: .whitespacesAndNewlines)).map(Date.init(timeIntervalSince1970:))
        let tested = await coverage.map { found in
            let caveats = (found.onlySinceLastCommit ? [" Only runs since the branch's last commit count: the checkout's reflog couldn't be read to tell its runs."] : [])
                + (found.leftOut > 0 ? [" \(found.leftOut == 1 ? "1 earlier run" : "\(found.leftOut) earlier runs") past the time allowed \(found.leftOut == 1 ? "isn't" : "aren't") counted."] : [])
            let runs = found.at.count == 1 ? "the test run of \(stamp(found.at[0]))" : "the test runs of \(ResultBundle.joined(found.at.map(stamp)))"
            let older = lastCommit.flatMap { commit in (found.at.max() ?? .distantPast) < commit ? ", older than the branch's last commit (\(stamp(commit)))" : nil } ?? ""
            return "- From \(runs)\(older): \(found.said.sentence)" + caveats.joined()
        }
        let built = await warnings.map { "- \(when($0.what, at: modified($0.dated), lastCommit: lastCommit)): \($0.sentence)" }
        return [tested, built].compactMap { $0 }
    }

    /// How long the branch's runs' coverage may take together: the mod gives the whole evidence call 300 s
    /// (`EVIDENCE_TIMEOUT_MS`), of which its other reading takes about a second; the rest is left for a large app's slower
    /// `xccov` (docs/findings.md, *The branch's test runs*).
    static let coverageBudget = Duration.seconds(240)

    /// What the branch's test runs' coverage says together, newest first, within `coverageBudget`: each run written while
    /// the checkout was on this branch (`BranchRuns`), leaving out runs of no test, whose coverage holds nothing run.
    static func branchCoverage(change: GitChanges.Change, project: Project, machine: Machine) async -> (said: Said, at: [Date], onlySinceLastCommit: Bool, leftOut: Int)? {
        let runner = machine.runner
        let git: @Sendable ([String]) async -> CommandResult = { arguments in await runner.run(["git", "-C", project.root.path] + arguments, stdin: nil, timeout: .seconds(10)) }
        let mark = ResultBundle.completionMark
        let listed = RunLog.candidates(in: "result-bundles", project: project.root, home: machine.home) { $0.hasSuffix(".xcresult") || $0.hasSuffix(".xcresult" + mark) }
        let bundles = Dictionary(listed.map { (path: $0.path.hasSuffix(mark) ? String($0.path.dropLast(mark.count)) : $0.path, written: modified($0)) }.map { ($0.path, $0.written) }) { max($0, $1) }
        guard !bundles.isEmpty else { return nil }
        async let reflog = git(["reflog", "show", "HEAD", "--date=unix", "--format=%gd%x09%gs"])
        async let head = git(["rev-parse", "--abbrev-ref", "HEAD"])
        async let base = git(["log", "-1", "--format=%ct", change.since])
        async let last = git(["log", "-1", "--format=%ct"])
        let date = { (result: CommandResult) in TimeInterval(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)).map(Date.init(timeIntervalSince1970:)) }
        let branch = GitHead.firstLine(await head.stdout).flatMap { $0 == "HEAD" ? nil : $0 }
        let read = await reflog
        let chosen = BranchRuns.chosen(bundles.map { ($0.key, $0.value) }, reflog: read.succeeded ? read.stdout : nil, branch: branch, mergeBase: date(await base), lastCommit: date(await last))
        let deadline = ContinuousClock.now + coverageBudget
        var found: [(coverage: ChangedLineCoverage, at: Date)] = []
        var leftOut = 0
        for path in chosen.paths {
            guard ContinuousClock.now < deadline else { leftOut += 1; continue }
            let bundle = ResultBundle(path: path, runner: runner)
            if ResultBundle.counts(summary: await bundle.summary())?.ran == 0 { continue }
            if let coverage = await ChangedLineCoverage.of(bundle, change: { change }, project: project, using: runner) { found.append((coverage, bundles[path] ?? .distantPast)) }
        }
        guard !found.isEmpty, let sentence = ChangedLineCoverage.merged(found.map(\.coverage)).sentence else { return nil }
        return (("the test runs", URL(fileURLWithPath: chosen.paths[0]), sentence), found.map(\.at), chosen.onlySinceLastCommit, leftOut)
    }

    static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    /// `- +3 more`, past the tests listed.
    static func more(_ count: Int) -> [String] {
        count > mostTests ? ["- +\(count - mostTests) more"] : []
    }

    static func quoted(_ message: String) -> String {
        "\"\(message)\""
    }

    /// The text with every path in the project made relative to its root, every other absolute or home path cut to its
    /// file's name, and every UUID, a simulator's or a device's, replaced.
    static func scrubbed(_ text: String, roots: [String]) -> String {
        var text = text
        for root in Set(roots) where !root.isEmpty { text = text.replacingOccurrences(of: root + "/", with: "") }
        // A path starts the text, a `file://` URL, or follows what can't be part of a word, a web URL or a relative path.
        text = text.replacing(/(^|file:\/\/|[^\w:\/.])~?\/(?:[^\s\/"'()\[\],;`]+\/)+([^\s\/"'()\[\],;`]+)/) { ($0.output.1 == "file://" ? "" : $0.output.1) + $0.output.2 }
        // A simulator's UUID, and a physical device's id: 8 hex digits, then 16.
        return text.replacing(/[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}|[0-9A-Fa-f]{16})/, with: "<id>")
    }

    /// `From the test run of 2026-10-30 14:24 UTC`, said to be older than the branch's last commit when it is.
    static func when(_ what: String, at: Date, lastCommit: Date?) -> String {
        let said = "From \(what) of \(stamp(at))"
        guard let lastCommit, at < lastCommit else { return said }
        return "\(said), older than the branch's last commit (\(stamp(lastCommit)))"
    }

    static func stamp(_ date: Date) -> String {
        let style = Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits) UTC",
            timeZone: .gmt, calendar: Calendar(identifier: .gregorian))
        return date.formatted(style)
    }
}
