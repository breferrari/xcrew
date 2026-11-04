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
    /// With `--passed`: the tests the run's results list as passed, for the ledger; nil when not asked for or when they
    /// can't be read.
    public var passed: [PassedTest]?
    /// A build or test call whose result holds nothing in its server's own forms, and isn't an error: a call Claude moved
    /// to the background answers with Claude Code's handle, not the server's result. Absent otherwise.
    public var isUnread: Bool?
    /// A test run's result bundle, which the ledger keeps for a test's first red run.
    public var bundle: String?
    /// That another Xcode than the project's pin built, for a failure whose errors another SDK or toolchain gives: apart
    /// from the notes, since the mod shows it once a session for each pin.
    public var pinNote: String?
    /// The pin `pinNote` names, `26.5 (.xcode-version)`: the mod names each pin once a session, however the note is worded.
    public var pin: String?
    /// The task a call Claude Code moved to the background answers with, from its handle: the id its notification names.
    public var backgroundTask: String?
    /// The outcome comes from a run log's last verdict alone, with no result or bundle read: no test's own result.
    public var isVerdictOnly: Bool?
    /// Why the run failed when the cause is the Mac, with its fix (`Why`): the note that leads `notes`, apart, so the
    /// failures pane can open with it.
    public var cause: String?
    /// The run's Swift concurrency diagnostics, when its log holds at least `ConcurrencyReport.noteAt`: apart from the
    /// notes, for the mod to decide when Claude reads it.
    public var concurrency: ConcurrencySummary?
    /// The scheme the run's log names, when the report was read with its log: what the mod keys a backgrounded run by.
    public var scheme: String?

    /// The warnings in lines the branch changed, a few named, marked as xcrew's; nothing when there are none.
    static func warningsNote(_ inChanged: [ToolOutput.Warning], of total: Int) -> String? {
        warningsSentence(inChanged, of: total, rest: inTheResult).map { "xcrew: " + $0 }
    }

    /// Where a result's warnings are all listed, for the ones its note only counts.
    static let inTheResult = "the result lists them all above"

    /// The warnings in the lines this branch changed, a few named and the rest counted with `rest`, which says where they
    /// all are; every one without it.
    static func warningsSentence(_ inChanged: [ToolOutput.Warning], of total: Int, rest: String?) -> String? {
        guard !inChanged.isEmpty else { return nil }
        // Messages carry commas, so a semicolon parts them.
        let named = inChanged.map { "\(ToolOutput.basename($0.path ?? "")):\($0.line ?? 0) \($0.message)" }
        return "\(inChanged.count) of \(total) warnings are in lines this branch changed\(ResultBundle.listed(named, separator: "; ", rest: rest))."
    }

    /// What makes a run of no tests, after either note's evidence: the result doesn't tell them apart (docs/findings.md,
    /// *Discovered tests*).
    static let noTestsCause = "An -only-testing or -skip-testing filter whose target or class names match nothing does this, as do a test plan that skips the tests or leaves their target out and tests compiled out of the build; the result doesn't say which."

    /// A run of no tests whose filter matched some, which MobileBuildMCP lists, with the plan of several configurations
    /// its scheme runs by default.
    static func selectedNoneNote(discovered: Int, plan: TestPlans.Configured?) -> String {
        "xcrew: this test run executed no tests, though it reports SUCCEEDED and its filter matched \(discovered == 1 ? "1 test" : "\(discovered) tests"), which MobileBuildMCP lists as discovered: the filter matched, and none executed." + (plan.map { " " + $0.sentence } ?? "")
    }
    static let noTestsNote = "xcrew: this test run ran no tests (passed, failed and skipped are all 0), though it reports SUCCEEDED. \(noTestsCause)"
    /// The same, for a run whose text gave no count and whose result bundle counts 0 tests.
    static let noTestsInBundleNote = "xcrew: this test run ran no tests: its result bundle counts 0 tests, though it reports SUCCEEDED. \(noTestsCause)"

    /// The size at which Claude Code saves a text result to a file and leaves a notice in its place: 50,000 characters
    /// (code.claude.com/docs/en/mcp, *MCP output limits and warnings*, read October 2026; docs/findings.md), counted as
    /// JavaScript counts a string's length, in UTF-16 units. A saved result xcrew edits comes back in the notice's place
    /// only below it, JSON included, which the docs give no point of its own; one compacted is far below it.
    static let savedFrom = 50_000

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

    /// Each failed test's images, on its failure for the pane: those the notes list, and the count and folder of the rest,
    /// kept under its title or under the bundle's id for it in `resolutions`.
    static func attaching(_ images: [TestID: FailureImages], to failures: [ToolOutput.Failure], resolutions: [TestID: TestLookup.Resolution] = [:]) -> [ToolOutput.Failure] {
        failures.map { failure in
            guard failure.isTest else { return failure }
            let test = TestID(xcresultID: failure.title)
            let found = images[test] ?? resolutions[test]?.found.flatMap { images[$0] }
            return ToolOutput.Failure(title: failure.title, message: failure.message, where: failure.where, isTest: true, images: found?.shown, moreImages: found?.more, target: failure.target)
        }
    }

    /// The bundle's failed tests in the order the run reported them, the text's: the bundle lists its own by plan,
    /// target and suite. Each test the text lists takes its place there, with the bundle's name and content, the text's
    /// message and place where the bundle gives none. A test is matched by its own name among `bundled`, else by
    /// `resolutions`, the bundle's id for it by the rule `TestLookup` keeps, as a nested suite's test from
    /// its outermost suite; a test with none is matched by its own name alone. A test only the bundle lists comes after;
    /// the text's other failures stay where they were. A test the text lists that matches none of the bundle's failures,
    /// as one several ids end with, disagrees with the bundle, and is returned once as disagreeing: one among `cleared`,
    /// which the bundle counts as passed, skipped or an expected failure in every entry, configuration and device under
    /// that name, as a retry it passed, is none of the run's failures; any other stays a failure in its place as the text
    /// gives it, since no entry, an entry with no result, or another result is no sign it passed.
    static func inRunOrder(_ bundled: [ToolOutput.Failure], text: [ToolOutput.Failure], cleared: Set<TestID>, resolutions: [TestID: TestLookup.Resolution] = [:]) -> (failures: [ToolOutput.Failure], disagreeing: [TestID]) {
        var pending = bundled.map { (test: TestID(xcresultID: $0.title), failure: $0) }
        let named = Set(pending.map(\.test))
        var ordered: [ToolOutput.Failure] = []
        var disagreeing: [TestID] = []
        for failure in text {
            guard failure.isTest else {
                ordered.append(failure)
                continue
            }
            let test = TestID(xcresultID: failure.title)
            let resolution = named.contains(test) ? .found(test) : resolutions[test] ?? .missing
            let found = resolution.found
            if let found, let index = pending.firstIndex(where: { $0.test == found }) {
                ordered.append(pending.remove(at: index).failure.filling(from: failure))
            } else if found.map(named.contains) != true {
                if !disagreeing.contains(test) {
                    disagreeing.append(test)
                    if !cleared.contains(test) { ordered.append(failure) }
                }
            }
        }
        return (ordered + pending.map(\.failure), disagreeing)
    }

    /// Of `failures`, the bundle's, those `text` doesn't list, by message and place, `exempt` kept whatever the text lists:
    /// a failure the text lists under a name that matched none of the bundle's ids, as a display name, is still the
    /// text's, so it gets no line of its own. Only an entry whose name `unresolved` says matched no id counts, each for one
    /// failure. An entry's message is what follows its `Suite / name: `, and its place the first its lines name, a path or
    /// a file alone, up to the blank line that ends it. A failure with no place is never the text's. Two of the bundle's
    /// failures with one message at one place, matching one such entry, are told apart by nothing: the first in the
    /// bundle's list takes it.
    static func notListedByText(_ failures: [(TestID, ToolOutput.Failure)], in text: MobileText, exempt: Set<TestID>, unresolved: (TestID) -> Bool) -> [(TestID, ToolOutput.Failure)] {
        var listed: [String: Int] = [:]
        for (index, line) in text.lines.enumerated() {
            guard case let .entry(entry) = line.kind, entry.failing.map({ unresolved($0.test) }) ?? true,
                  let named = entry.text.range(of: " / "), let colon = entry.text[named.upperBound...].range(of: ": ") else { continue }
            let below = text.lines[(index + 1)...].prefix { line in
                if case .entry = line.kind { return false }
                return !line.isBlank
            }
            let place = below.lazy.compactMap { line in
                line.location.map { "\(ToolOutput.basename($0.path)):\($0.line)" }
                    ?? line.text.trimmingCharacters(in: .whitespaces).wholeMatch(of: /[^\s\/]+\.\w+:\d+/).map { String($0.output) }
            }.first
            if let place { listed["\(entry.text[colon.upperBound...])\n\(place)", default: 0] += 1 }
        }
        return failures.filter { test, failure in
            guard !exempt.contains(test), let place = failure.where else { return true }
            let key = "\(failure.message)\n\(place)"
            guard let count = listed[key], count > 0 else { return true }
            listed[key] = count - 1
            return false
        }
    }

    /// The note on each failed test a name MobileBuildMCP's text gives can mean, when several can.
    static func reported(_ name: TestID, matching candidates: [TestID]) -> String {
        "MobileBuildMCP reported \"\(name.shown)\", which matches these \(candidates.count) tests: \(FailureNotes.candidates(candidates))"
    }

    /// The label on a failure line the bundle's list adds, where the text lists the test `outcome`, as passed.
    static func listedOtherwise(_ outcome: String) -> String {
        "the result bundle's; MobileBuildMCP's text lists it as \(outcome)"
    }

    /// The tests the text lists as failed that aren't among the bundle's failures, each with what the bundle records
    /// under the name the text gives, `results` each recorded test's results: every one it records, the clearing ones
    /// first, as passed and skipped for one skipped under another configuration. It names `ResultBundle.mostNamed` at
    /// most and counts the rest, each among MobileBuildMCP's failures in the result. Nil when there are none.
    static func notFailedInBundleNote(_ tests: [TestID], results: [TestID: Set<String>], ambiguous: Set<TestID> = []) -> String? {
        guard !tests.isEmpty else { return nil }
        let cleared = ResultBundle.cleared(in: results)
        let shown = tests.prefix(ResultBundle.mostNamed)
        let named = shown.map { test in
            if ambiguous.contains(test) { return "\(test.shown), which names more than one of the bundle's tests" }
            guard let found = results[test] else { return "\(test.shown), which the bundle has no entry for under that name" }
            let worded = ResultBundle.clearing.filter { found.contains($0.result) }.map(\.counts) + found.subtracting(ResultBundle.clearingResults).subtracting([ResultBundle.noResult]).map { $0.lowercased() }.sorted()
            if cleared.contains(test) { return "\(test.shown), which the bundle counts as \(ResultBundle.joined(worded, rest: "the rest of them"))" }
            let recorded = (worded.isEmpty ? [] : ["as " + ResultBundle.joined(worded, rest: "the rest of them")]) + (found.contains(ResultBundle.noResult) ? ["with no result"] : [])
            return "\(test.shown), which the bundle records \(recorded.joined(separator: worded.count > 1 ? ", and " : " and "))"
        }
        let these = tests.count == 1 ? "a test its result bundle doesn't list among its failures under that name" : "tests its result bundle doesn't list among its failures under that name"
        let clearing = ResultBundle.joined(ResultBundle.clearing.map(\.counts), or: true, rest: "the rest of them")
        let leftOut = shown.contains(where: cleared.contains) ? " A test the bundle counts as \(clearing) in every entry, test plan configuration and device is left out of the failures here." : ""
        let kept = shown.contains { !cleared.contains($0) } ? " A test the bundle doesn't count as \(clearing) in every entry, test plan configuration and device stays in the failures here, as MobileBuildMCP gives it." : ""
        let more = tests.count > ResultBundle.mostNamed ? "; and \(tests.count - ResultBundle.mostNamed) more, each among MobileBuildMCP's failures in the result" : ""
        return "xcrew: MobileBuildMCP's result lists as failed \(these): \(named.joined(separator: "; "))\(more).\(leftOut)\(kept)"
    }

    /// A summary that names its first failing test, naming `first` in place of `named`, the text's first, when that one
    /// is no failure, and after it when the text names none. With no failing test, `first` nil, the one the text named
    /// goes. The summary is one line, shortened, which can cut the name it ends with: a cut name is matched by its start,
    /// and what this gives is shortened again. Only a failed run's counts, `N of M failed`, get a test named after them.
    static func naming(_ detail: String?, first: String?, insteadOf named: String?) -> String? {
        guard let detail else { return nil }
        // A text that names no failing test, as one in a shape it isn't read in, gets the first in the same form.
        let separator = ToolOutput.Summary.beforeFirstFailing
        guard let named else {
            guard let first, ToolOutput.Summary.isFailedCounts(detail[...]) else { return detail }
            return ToolOutput.shorten(detail + separator + first)
        }
        guard first != named else { return detail }
        let base: Substring
        if detail.hasSuffix(separator + named) {
            base = detail.dropLast((separator + named).count)
        } else if detail.hasSuffix("…"), let cut = detail.ranges(of: separator).first(where: { named.hasPrefix(detail[$0.upperBound...].dropLast()) }) {
            base = detail[..<cut.lowerBound]
        } else {
            return detail
        }
        guard ToolOutput.Summary.isFailedCounts(base) else { return detail }
        return ToolOutput.shorten(String(base) + (first.map { separator + $0 } ?? ""))
    }

    /// The task Claude Code named in a handle: the one after "moved to the background as task", in each of its wordings
    /// (docs/findings.md, *A call moved to the background*). A server-side task's own id comes earlier and isn't it.
    static func backgroundTask(in text: String) -> String? {
        text.firstMatch(of: #/moved to the background as task ([A-Za-z0-9_-]+)/#).map { String($0.output.1) }
    }

    /// No outcome: what a call moved to the background answers with, or a task that ended with no result to read.
    public static let unread = Report(ok: false, failures: [], notes: [], isUnread: true)

    /// A finished run told from its MobileBuildMCP log, for a task whose result couldn't be read: the log's last verdict,
    /// and for a test run each failing test from the result bundle the log names, with each repeated test's runs when
    /// `repeated`. Without a bundle `xcresulttool` reads, the verdict alone, said to be so. Without a verdict, a log that
    /// xcodebuild ended with its own error failed with that error; any other, no outcome.
    public static func make(kind: Kind, log: String, runner: any CommandRunning, repeated: Bool = false, listsPassed: Bool = false) async -> Report {
        guard let ok = RunLog.outcome(of: log, kind: kind) else {
            guard let error = RunLog.lastError(in: log) else { return unread }
            return Report(ok: false, failures: [ToolOutput.Failure(error: error)], notes: [], isVerdictOnly: true)
        }
        let path = kind == .test ? RunLog.resultBundle(in: log) : nil
        if let path {
            let listing = TestList(await ResultBundle(path: path, runner: runner).tests())
            if let failed = ResultBundle.failedTests(listing: listing) {
                return Report(ok: ok, failures: ok ? [] : failed, notes: [], repeated: repeated ? ResultBundle.repetitions(listing: listing) : nil, passed: listsPassed ? ResultBundle.passed(listing: listing) : nil, bundle: path)
            }
        }
        return Report(ok: ok, failures: [], notes: [], bundle: path, isVerdictOnly: true)
    }

    /// A call moved to the background, from its task's notification: the server's text, of a task that completed or
    /// failed, read as the call's own, its shorter result put back in the notification Claude reads. MobileBuildMCP's text
    /// on one line, as a failed task's comes, is read on its own lines, and goes back on them; cut before the files that
    /// name its result bundle, it reads the bundle its log names. Else the run's log at
    /// `log`, when there is one, read with `launches` as a call's that installs and launches after its build, whose
    /// build's success is no outcome; else no outcome.
    public static func make(kind: Kind, notification text: String, log: String?, launches: Bool = false, server: Server, home: String, runner: any CommandRunning, repeated: Bool = false, listsPassed: Bool = false, project: Project? = nil, machine: Machine? = nil) async -> Report {
        let notification = TaskNotification(text)
        // A failed task's text is the run's only when it's in MobileBuildMCP's own forms: "the server went away" is no run.
        if let notification, let output = notification.serverOutput {
            let unfolded = server == .mobileBuildMCP ? OneLineText.unfolded(output.text) : nil
            let text = unfolded ?? output.text
            let given = ToolOutput(text: text, server: server, isError: output.isError)
            if !(output.isError && given.isNotTheServers) {
                let logged = unfolded != nil && given.xcresultPath == nil ? log.flatMap { RunLog.resultBundle(in: RunLog.text(ofLogAt: $0)) } : nil
                var read = await make(kind: kind, output: given, home: home, runner: runner, repeated: repeated, listsPassed: listsPassed, project: project, machine: machine, bundle: logged)
                if read.isUnread != true {
                    if let shorter = read.result ?? unfolded { read.result = notification.replacingResult(with: shorter) }
                    return read
                }
            }
        }
        guard let log else { return unread }
        return await make(kind: launches ? .run : kind, log: RunLog.text(ofLogAt: log), runner: runner, repeated: repeated, listsPassed: listsPassed)
    }

    /// A result Claude Code saved to a file is read back from it. A test run's result bundle is the one its text names,
    /// else `logged`, the one its log names, for a text cut before it names one.
    public static func make(kind: Kind, output: ToolOutput, home: String, runner: any CommandRunning, repeated: Bool = false, listsPassed: Bool = false, project: Project? = nil, machine: Machine? = nil, bundle logged: String? = nil) async -> Report {
        let saved = savedPath(output.text)
        let read = saved.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }.map { ToolOutput(text: $0, server: output.server, isError: output.isError) } ?? output
        let isTest = kind == .test
        // MobileBuildMCP's text omits what its result bundle knows; the Xcode MCP's results carry their own.
        let bundle = isTest ? (ResultBundle.path(in: read, home: home) ?? logged).map { ResultBundle(path: $0, runner: runner) } : nil
        // The summary is needed whatever the run came to, so it's asked for while the failures are looked up.
        async let bundleSummary: String? = { await bundle?.summary() }()
        // MobileBuildMCP writes "Test succeeded" with no count when no test ran and when it couldn't count them alike: the
        // run's result bundle says which, before anything below branches on the verdict or the count. Without a summary to
        // read, it stays a pass with no count.
        let bundleCounts = read.mobileText?.isUncountedSuccess == true ? await bundleSummary.flatMap(ResultBundle.counts(summary:)) : nil
        let readSummary = bundleCounts.map { $0.summary(succeeded: read.summary.ok) } ?? read.summary
        // What the branch changed is listed once, by whichever asks first, meanwhile: for the warnings that name a
        // place, and for a test run with coverage.
        let warnings = read.warnings
        let change = Once { () async -> GitChanges.Change? in
            guard let project, case let .success(change) = await GitChanges.since(nil, in: project, using: runner) else { return nil }
            return change
        }
        async let inChanged: [ToolOutput.Warning]? = {
            guard let project, warnings.contains(where: { $0.path != nil }), let listed = await change.value() else { return nil }
            return await ChangedLines.warnings(warnings, in: listed, project: project, using: runner)
        }()
        async let coverage: ChangedLineCoverage? = {
            // A run of no tests ran none of the changed lines, which says nothing of them.
            guard let project, let bundle, (bundleCounts?.ran ?? read.testTotal) != 0 else { return nil }
            // Behind the report's other reads in the pool: what failed is read first.
            let behind = CommandPool.lane(of: runner, 1)
            return await ChangedLineCoverage.of(ResultBundle(path: bundle.path, runner: behind, exportFolder: bundle.exportFolder), change: { await change.value() }, project: project, using: behind)
        }()
        async let why: String? = {
            guard let project, !readSummary.ok else { return nil }
            return await Why.note(for: read, home: home, project: project, runner: runner)
        }()
        // Which Xcode builds, for a failed MobileBuildMCP build or test whose errors another SDK or toolchain gives: the pin's
        // note, which the mod names once a session, and the notes on CI's Xcode, a pin to suggest, and the open Xcode.
        async let xcodeFacts: (pin: String?, notes: [String]) = {
            // MobileBuildMCP builds with the Xcode the pin decides; the Xcode MCP, with whichever is open.
            guard read.server == .mobileBuildMCP, let project, let machine, !readSummary.ok else { return (nil, []) }
            let errors = read.reportedErrors.map(\.message)
            // A test run whose build failed lists only that; the compiler's errors are in the build log it names. A failed
            // test's log holds the app's own output, so it isn't read.
            let buildFailed = kind == .test && !read.failures.contains(where: \.isTest) && errors.contains { $0.hasPrefix("Failed to build") }
            let logged = { buildFailed ? read.buildLog(home: home).flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }.map { BuildLog.errors(in: $0).map(\.message) } ?? [] : [] }
            guard errors.contains(where: XcodePinCheck.mayBeTheToolchain) || logged().contains(where: XcodePinCheck.mayBeTheToolchain) else { return (nil, []) }
            let xcodes = await XcodeSnapshot.take(of: project, on: machine)
            return (XcodePinCheck.failureNote(xcodes, hasXcodes: machine.runner.which("xcodes") != nil), XcodeFailureNotes.notes(xcodes))
        }()
        async let concurrency: ConcurrencySummary? = {
            // MobileBuildMCP's result lists each diagnostic once: one listing fewer than the note's count can't hold that
            // many concurrency ones, so its log isn't read.
            guard read.server == .mobileBuildMCP, let project, let machine, warnings.count + read.reportedErrors.count >= ConcurrencyReport.noteAt,
                  let log = read.buildLog(home: home) else { return nil }
            return try? await ConcurrencyReport.read(log: URL(fileURLWithPath: log), project: project, machine: machine, readsChanges: false).summary
        }()
        var final = read
        var edited = false
        var images: [TestID: FailureImages] = [:]
        // Only the warnings in lines this branch changed are listed, Claude's to fix; the rest are counted, with where the
        // full list is: the saved result, else the run's build log. Without the branch's changes, every one stays.
        let changedWarnings = await inChanged
        if let changedWarnings, let kept = read.keepingWarnings(Set(changedWarnings), pointer: saved ?? read.buildLog(home: home) ?? "the run's build log") {
            (final, edited) = (kept, true)
        }
        if let collapsed = final.collapsingWarnings() { (final, edited) = (collapsed, true) }
        // The run's test list, parsed once, when the first question needs it; none without a bundle.
        var parsed: TestList?
        func testList() async -> TestList {
            if let parsed { return parsed }
            let list = TestList(await bundle?.tests() ?? "")
            parsed = list
            return list
        }
        var built: TestLookup?
        func testLookup() async -> TestLookup {
            if let built { return built }
            let made = TestLookup(nodes: await testList().nodes)
            built = made
            return made
        }
        // A repeated run's tests, each with how many of its runs failed: the notes count them, and the verdicts read them.
        let repetitions = if repeated, bundle != nil { ResultBundle.repetitions(listing: await testList()) } else { [ResultBundle.Repeated]() }
        var bundleIDs: [TestID: TestLookup.Resolution] = [:]
        var labels: [TestID: String] = [:]
        if var text = final.mobileText {
            var changed = false
            if let cleaned = text.withoutExcerpts() { (text, changed) = (cleaned, true) }
            // A repeated run's text lists no failures, and with test timing on, each test once for each run.
            if bundle != nil, text.isTestRun, !repetitions.isEmpty {
                if let added = text.addingFailures(ResultBundle.repeatedFailures(listing: await testList())) { (text, changed) = (added, true) }
                if text.testResultsStart != nil {
                    let lookup = await testLookup()
                    if let once = text.listingRunsOnce(repetitions, resolving: { lookup.resolution(of: $0).found ?? $0 }) { (text, changed) = (once, true) }
                }
            }
            if bundle != nil, text.isTestRun, !final.summary.ok {
                let listing = await testList()
                let lookup = await testLookup()
                bundleIDs = Dictionary(text.lines.compactMap { $0.failing?.test }.map { ($0, lookup.resolution(of: $0)) }) { first, _ in first }
                let named = Set(bundleIDs.values.compactMap(\.found)).union(bundleIDs.keys)
                let notNamed = (ResultBundle.failedTests(listing: listing) ?? []).map { (TestID(xcresultID: $0.title), $0) }.filter { !named.contains($0.0) }
                let failed = Set(notNamed.map(\.0))
                let reported = bundleIDs.compactMapValues { resolution -> [TestID]? in
                    if case let .ambiguous(ids) = resolution, ids.contains(where: failed.contains) { ids } else { nil }
                }
                let ambiguousIDs = Set(reported.values.joined())
                let unlisted = Self.notListedByText(notNamed, in: text, exempt: ambiguousIDs) { bundleIDs[$0]?.found == nil }
                let entries = unlisted.map { test, failure in (test: test, message: failure.message, id: lookup.resolution(of: test).found ?? test) }
                let listed = { (entry: (test: TestID, message: String, id: TestID)) -> MobileText.FailureLine in
                    (test: entry.test, message: entry.message, place: ResultBundle.place(of: entry.id, in: lookup.cases))
                }
                let said = unlisted.isEmpty ? [] : text.lines.compactMap { line -> (TestID, String)? in
                    if let test = MobileBuildMCPLine.passed(line.text) { return (test, "passed") }
                    if case let .skipped(test?) = line.kind { return (test, "skipped") }
                    return nil
                }
                let outcomes = Dictionary(said.map { (lookup.resolution(of: $0.0).found ?? $0.0, $0.1) }) { first, _ in first }
                labels = Dictionary(entries.compactMap { entry in outcomes[entry.id].map { (entry.test, Self.listedOtherwise($0)) } }) { first, _ in first }
                var placed: Set<TestID> = []
                for (name, ids) in reported.sorted(by: { $0.key.shown < $1.key.shown }) {
                    let candidateIDs = Set(ids)
                    let candidates = entries.filter { candidateIDs.contains($0.test) && !placed.contains($0.test) }
                    for candidate in candidates { labels[candidate.test] = Self.reported(name, matching: ids) }
                    guard let swapped = text.replacing(name, with: candidates.map(listed)) else { continue }
                    (text, changed) = (swapped.text, true)
                    placed.formUnion(candidates.map(\.test))
                    if swapped.left == 0 { bundleIDs[name] = nil }
                }
                if let added = text.adding(unlisted: entries.filter { !placed.contains($0.test) }.map(listed)) { (text, changed) = (added, true) }
                for entry in entries { bundleIDs[entry.test] = .found(entry.id) }
            }
            if let bundle, text.isTestRun, let pending = await FailureNotes.lookingUp(text, from: bundle, keepingImagesIn: machine.map { ($0.cacheFolder.appending(path: "images"), $0.now()) }, repetitions: repetitions, bundleIDs: bundleIDs, labels: labels),
               let annotated = pending.adding(skips: pending.readsSkips ? ResultBundle.skippedTests(listing: await testList()) : []) {
                (final, edited, images) = (ToolOutput(annotated.text, isError: output.isError), true, annotated.images)
            } else if changed {
                (final, edited) = (ToolOutput(text, isError: output.isError), true)
            }
        }
        var summary = bundleCounts.map { $0.summary(succeeded: final.summary.ok) } ?? final.summary

        var notes = ToolErrorNotes.notes(for: output)
        let runScheme = { read.buildLog(home: home).flatMap { RunLog.scheme(ofLogAt: URL(fileURLWithPath: $0)) } }
        // Xcode refused the run's filter: that, not an empty filter or plan, is why none ran.
        let refused = isTest && read.server == .mobileBuildMCP ? OutsideScheme.targets(in: read.text) : []
        if let project, !refused.isEmpty { notes.append(OutsideScheme.note(targets: refused, scheme: runScheme(), in: project)) }
        let tests = bundleCounts?.ran ?? final.testTotal
        if isTest, tests == 0, refused.isEmpty {
            if let discovered = read.discovered, discovered > 0 {
                // The filter matched: none ran is what happened, not that no test was there to run.
                summary = ToolOutput.Summary(ok: false, detail: "\(discovered) selected, none ran")
                notes.append(selectedNoneNote(discovered: discovered, plan: project.flatMap { project in runScheme().flatMap { TestPlans.configured(forScheme: $0, in: project) } }))
            } else {
                notes.append(bundleCounts == nil ? noTestsNote : noTestsInBundleNote)
            }
        }
        if bundle != nil, let summary = await bundleSummary {
            // The test list is only asked for when the summary counts expected failures to name.
            let listing = ResultBundle.expectedFailureCount(summary: summary) > 0 ? await testList() : TestList("")
            if let expected = ResultBundle.expectedFailuresNote(summary: summary, names: ResultBundle.expectedFailures(listing: listing), knownIssues: ResultBundle.knownIssues(listing: listing)) { notes.append(expected) }
        }
        // A run repeated with `-test-iterations` says, per test, whether it's flaky or failing for real.
        var repeatedTests: [ResultBundle.Repeated]?
        if repeated {
            notes.append(ResultBundle.repetitionsNote(repetitions) ?? ResultBundle.noRepetitionsNote)
            repeatedTests = repetitions
        }

        // The warnings in lines this branch changed, named: those are Claude's to fix. Nothing is said about the rest, or
        // about warnings the change causes in lines it left alone.
        if let changedWarnings, let note = warningsNote(changedWarnings, of: warnings.count) { notes.append(note) }

        if let note = await coverage?.note { notes.append(note) }

        // A run that failed because of the Mac says so first: its errors would read as the code's.
        if let why = await why { notes.insert(why, at: 0) }

        // Which Xcode builds, where it can explain the failure.
        notes += await xcodeFacts.notes

        // A failing test run's failed tests are its result bundle's, each failing test's target too, and the text's that
        // the bundle doesn't count as no failure; all the text's without a test list to read. Its other failures, the
        // build's and the process's, are the text's.
        let listing = if bundle != nil, isTest, !summary.ok { await testList() } else { TestList("") }
        let bundled = ResultBundle.failedTests(listing: listing)
        let recorded = bundled == nil ? [:] : ResultBundle.results(in: listing.nodes)
        let unresolved = Set(final.failures.filter(\.isTest).map { TestID(xcresultID: $0.title) }.filter { bundleIDs[$0] == nil })
        var resolutions = bundleIDs
        if !unresolved.isEmpty, bundled != nil {
            let lookup = await testLookup()
            for test in unresolved { resolutions[test] = lookup.resolution(of: test) }
        }
        let results = recorded.merging(resolutions.compactMap { test, resolution in
            resolution.found.flatMap { recorded[$0] }.map { (test, $0) }
        }) { own, _ in own }
        let ordered = bundled.map { Self.inRunOrder($0, text: final.failures, cleared: ResultBundle.cleared(in: results), resolutions: resolutions) }
        let failures = ordered?.failures ?? final.failures
        if let ordered, let note = Self.notFailedInBundleNote(ordered.disagreeing, results: results, ambiguous: Set(resolutions.filter(\.value.isAmbiguous).keys)) { notes.append(note) }
        // The tests the run passed, asked for by the ledger: the Xcode MCP's from its results, MobileBuildMCP's from its
        // bundle, whose test list is read once however many ask.
        var passedTests: [PassedTest]?
        if listsPassed, isTest {
            if read.server == .xcode {
                passedTests = final.passedTests
            } else if bundle != nil {
                passedTests = ResultBundle.passed(listing: await testList())
            }
        }
        let isUnread = kind != .run && !final.isError && final.isNotTheServers
        let compact = saved.flatMap { final.compactTestResult(savedPath: $0) } ?? (saved == nil ? final.compactTestText : nil)
        // What xcrew made of the result comes back in its place, but for a saved result only once it's under the size Claude
        // Code saves: compacting leaves the errors and failures, which can run long themselves.
        let shortened = compact ?? (edited ? final.text : nil)
        let comesBack = shortened.map { saved == nil || $0.utf16.count < Self.savedFrom } ?? false
        return Report(
            ok: summary.ok,
            detail: Self.naming(summary.detail, first: failures.first(where: \.isTest)?.title, insteadOf: final.failures.first(where: \.isTest)?.title),
            durationMs: final.reportedDuration,
            tests: tests,
            failures: summary.ok ? [] : Self.attaching(images, to: failures, resolutions: resolutions),
            result: comesBack ? shortened : nil,
            notes: notes,
            repeated: repeatedTests,
            passed: passedTests,
            isUnread: isUnread ? true : nil,
            bundle: bundle?.path,
            pinNote: await xcodeFacts.pin,
            pin: await xcodeFacts.pin == nil ? nil : project?.xcodePin.map { "\($0.version) (\($0.file))" },
            backgroundTask: isUnread ? Self.backgroundTask(in: final.text) : nil,
            cause: await why,
            concurrency: await concurrency
        )
    }
}
