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
    /// all are, or that no list is kept.
    static func warningsSentence(_ inChanged: [ToolOutput.Warning], of total: Int, rest: String) -> String? {
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

    /// Each failed test's images, on its failure for the pane: those the notes list, and the count and folder of the rest.
    static func attaching(_ images: [TestID: FailureImages], to failures: [ToolOutput.Failure]) -> [ToolOutput.Failure] {
        failures.map { failure in
            guard failure.isTest else { return failure }
            let found = images[TestID(xcresultID: failure.title)]
            return ToolOutput.Failure(title: failure.title, message: failure.message, where: failure.where, isTest: true, images: found?.shown, moreImages: found?.more, target: failure.target)
        }
    }

    /// The bundle's failed tests in the order the run reported them, the text's: the bundle lists its own by plan,
    /// target and suite. Each test the text lists takes its place there, with the bundle's name and content, the text's
    /// message and place where the bundle gives none. The text names a nested suite's test from its own suite, and the
    /// bundle from the outermost: it's matched by the end of the bundle's name for it, when no other's ends the same way
    /// and none is the text's whole. A test only the bundle lists comes after; the text's other failures stay where
    /// they were. A test only the text lists, as a retry the bundle counts passed, is none of the run's failures.
    static func inRunOrder(_ bundled: [ToolOutput.Failure], text: [ToolOutput.Failure]) -> [ToolOutput.Failure] {
        var pending = bundled.map { (test: TestID(xcresultID: $0.title), failure: $0) }
        let named = Set(pending.map(\.test))
        var ordered: [ToolOutput.Failure] = []
        for failure in text {
            guard failure.isTest else {
                ordered.append(failure)
                continue
            }
            let test = TestID(xcresultID: failure.title)
            let index = pending.firstIndex { $0.test == test } ?? {
                guard !named.contains(test) else { return nil }
                let nested = pending.indices.filter { test.isNested(in: pending[$0].test) }
                return nested.count == 1 ? nested.first : nil
            }()
            if let index {
                let found = pending.remove(at: index).failure
                ordered.append(ToolOutput.Failure(title: found.title, message: found.message.isEmpty ? failure.message : found.message, where: found.where ?? failure.where, isTest: true, target: found.target))
            }
        }
        return ordered + pending.map(\.failure)
    }

    /// The tests the text lists as failed that the bundle counts as passed, as one a retry passed; nil when the two
    /// agree.
    static func passedInBundleNote(text: [ToolOutput.Failure], listing: TestList) -> String? {
        let passed = ResultBundle.passedTests(listing: listing)
        let named = text.filter(\.isTest).map { TestID(xcresultID: $0.title) }.filter(passed.contains).map(\.shown)
        guard !named.isEmpty else { return nil }
        let tests = named.count == 1 ? "a test the result bundle counts as passed" : "tests the result bundle counts as passed"
        return "xcrew: MobileBuildMCP's text lists as failed \(tests): \(named.joined(separator: ", ")). The failures listed here are the bundle's."
    }

    /// A summary that names its first failing test, naming `first` in place of `named`, the text's first, when that one
    /// is no failure, and after it when the text names none. With no failing test, the one the text named goes: the
    /// failures come from the text unless the bundle listed them, so it named a test the bundle doesn't count as failed.
    static func naming(_ detail: String?, first: String?, insteadOf named: String?) -> String? {
        guard let detail else { return nil }
        // A text that names no failing test, as one in a shape it isn't read in, gets the first in the same form.
        guard let named else { return detail.hasSuffix(ToolOutput.Summary.failedCounts) ? first.map { detail + ToolOutput.Summary.beforeFirstFailing + $0 } ?? detail : detail }
        let naming = ToolOutput.Summary.beforeFirstFailing + named
        guard first != named, detail.hasSuffix(naming) else { return detail }
        return String(detail.dropLast(naming.count)) + (first.map { ToolOutput.Summary.beforeFirstFailing + $0 } ?? "")
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
    /// `repeated`. Without a bundle `xcresulttool` reads, the verdict alone, said to be so; without a verdict, no outcome.
    public static func make(kind: Kind, log: String, runner: any CommandRunning, repeated: Bool = false, listsPassed: Bool = false) async -> Report {
        guard let ok = RunLog.outcome(of: log, kind: kind) else { return unread }
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
    /// failed, read as the call's own, its shorter result put back in the notification Claude reads; else the run's log at
    /// `log`, when there is one, read with `launches` as a call's that installs and launches after its build, whose
    /// build's success is no outcome; else no outcome.
    public static func make(kind: Kind, notification text: String, log: String?, launches: Bool = false, server: Server, home: String, runner: any CommandRunning, repeated: Bool = false, listsPassed: Bool = false, project: Project? = nil, machine: Machine? = nil) async -> Report {
        let notification = TaskNotification(text)
        // A failed task's text is the run's only when it's in MobileBuildMCP's own forms: "the server went away" is no run.
        if let notification, let output = notification.serverOutput, !(output.isError && ToolOutput(text: output.text, server: server, isError: true).isNotTheServers) {
            var read = await make(kind: kind, output: ToolOutput(text: output.text, server: server, isError: output.isError), home: home, runner: runner, repeated: repeated, listsPassed: listsPassed, project: project, machine: machine)
            if read.isUnread != true {
                if let shorter = read.result { read.result = notification.replacingResult(with: shorter) }
                return read
            }
        }
        guard let log else { return unread }
        return await make(kind: launches ? .run : kind, log: RunLog.text(ofLogAt: log), runner: runner, repeated: repeated, listsPassed: listsPassed)
    }

    /// A result Claude Code saved to a file is read back from it.
    public static func make(kind: Kind, output: ToolOutput, home: String, runner: any CommandRunning, repeated: Bool = false, listsPassed: Bool = false, project: Project? = nil, machine: Machine? = nil) async -> Report {
        let saved = savedPath(output.text)
        let read = saved.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }.map { ToolOutput(text: $0, server: output.server, isError: output.isError) } ?? output
        let isTest = kind == .test
        // MobileBuildMCP's text omits what its result bundle knows; the Xcode MCP's results carry their own.
        let bundle = isTest ? ResultBundle.path(in: read, home: home).map { ResultBundle(path: $0, runner: runner) } : nil
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
        // A repeated run's tests, each with how many of its runs failed: the notes count them, and the verdicts read them.
        let repetitions = if repeated, bundle != nil { ResultBundle.repetitions(listing: await testList()) } else { [ResultBundle.Repeated]() }
        if var text = final.mobileText {
            var changed = false
            if let cleaned = text.withoutExcerpts() { (text, changed) = (cleaned, true) }
            // A repeated run's text lists no failures, and with test timing on, each test once for each run.
            if bundle != nil, text.isTestRun, !repetitions.isEmpty {
                if let added = text.addingFailures(ResultBundle.repeatedFailures(listing: await testList())) { (text, changed) = (added, true) }
                if let once = text.listingRunsOnce(repetitions) { (text, changed) = (once, true) }
            }
            if let bundle, text.isTestRun, let pending = await FailureNotes.lookingUp(text, from: bundle, keepingImagesIn: machine.map { ($0.cacheFolder.appending(path: "images"), $0.now()) }, repetitions: repetitions),
               // The test list is read for the skips once the failures are looked up: what failed is read first.
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

        // A failing test run's failed tests are its result bundle's, each failing test's target too; the text's only
        // without a test list to read. Its other failures, the build's and the process's, are the text's.
        let listing = if bundle != nil, isTest, !summary.ok { await testList() } else { TestList("") }
        let bundled = ResultBundle.failedTests(listing: listing)
        let failures = bundled.map { Self.inRunOrder($0, text: final.failures) } ?? final.failures
        if bundled != nil, let note = Self.passedInBundleNote(text: final.failures, listing: listing) { notes.append(note) }
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
            failures: summary.ok ? [] : Self.attaching(images, to: failures),
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
