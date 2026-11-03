import Foundation

/// What a run kept about the moment each failed UI test failed, for Claude to look at before changing a test or a view:
/// per failed run, its configuration and device, the steps before the failure, the failure, and the screen at it.
public enum Look {
    /// Failed UI tests shown when none is named; the rest are named for a later look.
    static let mostTests = 3
    /// Elements of a hierarchy shown under a failed run; the rest are counted, with the file that holds them all.
    static let mostElements = 30

    /// What `look` says about one test in `bundle`, or, with none named, about its failed UI tests: those whose failed
    /// runs kept a screen recording. Screens are kept under `folder`, in a folder per run, and runs kept there too long
    /// before `now` are removed.
    public static func report(bundle: ResultBundle, named: String?, keptIn folder: URL, now: Date) async -> String {
        let listing = TestList(await bundle.tests())
        let cases = ResultBundle.testCases(in: listing.nodes)
        return await report(bundle: bundle, test: named.map { test($0, among: cases) }, cases: cases, failed: listing.json == nil ? nil : ResultBundle.failedTests(in: listing.nodes), keptIn: folder, now: now)
    }

    /// The test a name means, among the bundle's: the name as given, `()` or not, else the name without its first part,
    /// which `-only-testing:` spells as the target (`Target/Suite/test`), a nested suite's `/` kept either way; else, as
    /// the run's text names a test, the one nested id that ends with it, or the `System Failures` case a crash of it is
    /// filed under. When the bundle lists none, a name ending `()` is taken as the bundle's own and one without as
    /// `-only-testing:`'s.
    static func test(_ named: String, among cases: [TestID: [[String: Any]]]) -> TestID {
        let exact = TestID(xcresultID: named)
        let parts = named.split(separator: "/", maxSplits: 1)
        let withoutTarget = parts.count > 1 && parts[1].contains("/") ? TestID(xcresultID: parts[1]) : nil
        if cases[exact] != nil { return exact }
        if let withoutTarget, cases[withoutTarget] != nil { return withoutTarget }
        let (ids, crashes) = (Set(cases.keys), ResultBundle.crashCases(in: cases.values.flatMap(\.self)))
        for candidate in [exact, withoutTarget].compactMap(\.self) {
            if let id = ResultBundle.resolution(of: candidate, among: ids, crashCases: crashes).found { return id }
        }
        return named.hasSuffix("()") ? exact : withoutTarget ?? exact
    }

    /// `failed` is the run's failed tests, nil when its test list couldn't be read. The run's size is recorded once all its
    /// tests are looked at: they're looked at side by side, and a measure taken before another's write would record too
    /// few.
    static func report(bundle: ResultBundle, test: TestID?, cases: [TestID: [[String: Any]]], failed: [TestID]?, keptIn folder: URL, now: Date) async -> String {
        let name = URL(fileURLWithPath: bundle.path).lastPathComponent
        let run = bundle.runFolder(in: folder)
        FailureImages.prune(in: folder, now: now)
        if let test {
            let passedUnder = FailedRun.passedConfigurations(of: cases[test] ?? [])
            guard let read = FailedRun.read(activities: await bundle.activities(of: test), passedUnder: passedUnder) else {
                return "xcrew: couldn't read \(test.shown)'s steps in \(name); xcrun xcresulttool get test-results activities --test-id \(test.xcresultID) --path \(bundle.path) says why"
            }
            let looked = await look(at: test, runs: read.failed, passed: read.passed, in: bundle, named: name, keptIn: run)
            FailureImages.record(run)
            return looked ?? "xcrew: \(test.shown) didn't fail in \(name)"
        }
        guard let failed else {
            return "xcrew: couldn't read the tests in \(name); xcrun xcresulttool get test-results tests --path \(bundle.path) says why"
        }
        guard !failed.isEmpty else { return "xcrew: nothing failed in \(name)" }
        // A few at a time, in the listing's order, until enough UI tests are found, every failed test if need be: a unit
        // test costs one read of its steps.
        var shown: [String] = []
        var unshown: [TestID] = []
        var next = 0
        while next < failed.count, shown.count < mostTests {
            let batch = Array(failed[next..<min(next + FailureNotes.mostAtOnce, failed.count)])
            next += batch.count
            let passedUnder = batch.map { FailedRun.passedConfigurations(of: cases[$0] ?? []) }
            let looked = await withTaskGroup(of: (Int, String?).self) { group in
                for (index, test) in batch.enumerated() {
                    let passed = passedUnder[index]
                    group.addTask {
                        guard let read = FailedRun.read(activities: await bundle.activities(of: test), passedUnder: passed),
                              read.failed.contains(where: \.hasRecording)
                        else { return (index, nil) }
                        return (index, await look(at: test, runs: read.failed, passed: read.passed, in: bundle, named: name, keptIn: run))
                    }
                }
                var found = [String?](repeating: nil, count: batch.count)
                for await (index, text) in group { found[index] = text }
                return found
            }
            for (test, text) in zip(batch, looked) {
                guard let text else { continue }
                if shown.count < mostTests { shown.append(text) } else { unshown.append(test) }
            }
        }
        FailureImages.record(run)
        guard !shown.isEmpty else {
            return "xcrew: no failed test in \(name) kept a screen recording, as a UI test's failed run does; xcrew look <Suite/test> shows one test's steps"
        }
        unshown += failed.dropFirst(next)
        let more = unshown.isEmpty ? [] : ["and \(unshown.count) more failed \(unshown.count == 1 ? "test" : "tests")" + ResultBundle.listed(unshown.map { "xcrew look \($0.shown)" }, rest: "`xcrun xcresulttool get test-results tests --path \(bundle.path)` lists them all")]
        return (shown + more).joined(separator: "\n")
    }

    /// One test's failed runs, each with its steps, failure and screen, then where it passed; nil when none failed. A
    /// run's screen is numbered when the test failed more than once on its device and configuration, as a repeated run
    /// does.
    static func look(at test: TestID, runs: [FailedRun], passed: [String], in bundle: ResultBundle, named name: String, keptIn run: URL) async -> String? {
        guard !runs.isEmpty else { return nil }
        // Numbered by the label the kept file is named by: parallel clones of one simulator share it.
        let numbers = runs.indices.map { index in
            runs.filter { $0.label == runs[index].label }.count > 1 ? runs[..<index].filter { $0.label == runs[index].label }.count + 1 : nil
        }
        // Every attachment, and only for runs that attached any, as a unit test's don't: the hierarchy is told by its
        // content, and the recordings make up nearly all of an export (docs/findings.md).
        let kept: [(screen: FailureScreen?, hierarchy: FailureHierarchy?)] = if runs.contains(where: { !$0.attachments.isEmpty }) {
            await bundle.attachments(of: test, onlyFailures: false) { export in
                let files = files(in: export)
                var kept: [(screen: FailureScreen?, hierarchy: FailureHierarchy?)] = []
                for (failed, number) in zip(runs, numbers) {
                    kept.append((await FailureScreen.keep(of: test, run: failed, number: number, files: files, in: run), FailureHierarchy.keep(of: test, run: failed, number: number, files: files, in: run)))
                }
                return kept
            }
        } else {
            runs.map { _ in (nil, nil) }
        }
        var lines = ["xcrew look: \(test.shown), in \(name)"]
        let onScreen = elements(of: zip(runs, kept).map { failed, found in (failed.label, failed.attachments.isEmpty ? nil : hierarchyLines(found.hierarchy, query: UIQuery(failure: failed.failure, steps: failed.steps), screenshot: found.screen != nil)) })
        for ((failed, found), elements) in zip(zip(runs, kept), onScreen) {
            lines.append("  " + failed.label)
            lines += failed.steps.map { "    \(firstLine($0))" }
            lines.append("    ✗ \(firstLine(failed.failure))")
            guard !failed.attachments.isEmpty else { continue }
            lines.append("    " + screenLine(found.screen, recorded: failed.hasRecording))
            lines += (elements ?? []).map { "    \($0)" }
        }
        if !passed.isEmpty { lines.append("  passed under: " + passed.joined(separator: "; ")) }
        return lines.joined(separator: "\n")
    }

    /// Said above the elements when a query found nothing and a screenshot shows what the hierarchy can't.
    static let appsOnly = "the elements below are the app's only; a system alert, as a permission request, shows only in the screenshot"

    static func screenLine(_ screen: FailureScreen?, recorded: Bool) -> String {
        guard let screen else { return recorded ? "screen: none; its recording couldn't be read" : "screen: none; the run kept no screen recording" }
        return screen.secondsBefore < 1 ? "screen: \(screen.path)" : "screen: \(screen.path) (\(Int(screen.secondsBefore.rounded())) s before the failure)"
    }

    /// Each run's elements on screen, as `hierarchyLines` lists them, nil for a run whose aren't listed: a list the same as
    /// an earlier run's is said once, by that run's label, as under a test plan's configurations whose screens hold the
    /// same elements. Two lists are the same though each names its own file for the elements past those listed; a run
    /// whose screen lists no element, as one that kept no hierarchy, says so itself.
    static func elements(of runs: [(label: String, lines: [String]?)]) -> [[String]?] {
        var listedUnder: [[String]: String] = [:]
        return runs.map { run in
            guard let lines = run.lines else { return nil }
            guard lines.count > 1 else { return lines }
            let same = lines.map { $0.firstMatch(of: #/^(  and \d+ more) in /#).map { String($0.1) } ?? $0 }
            if let first = listedUnder[same] { return ["on screen: the same as under \(first)"] }
            listedUnder[same] = run.label
            return lines
        }
    }

    /// The elements on screen at the failure, the query's marked or named missing; or, for a hierarchy in a shape xcrew
    /// doesn't read, its text as XCTest wrote it. The hierarchy XCTest attaches is the app's: a system alert belongs to
    /// another process, so when the query found nothing and there's a `screenshot`, the list says it shows only the app.
    static func hierarchyLines(_ kept: FailureHierarchy?, query: UIQuery?, screenshot: Bool) -> [String] {
        guard let kept else { return ["on screen: no hierarchy kept; XCTest attaches one when a query fails"] }
        let more = { (count: Int) in count > 0 ? ["  and \(count) more in \(kept.path)"] : [] }
        switch kept.content {
        case let .asWritten(text):
            let raw = text.split(separator: "\n").map(String.init)
            return ["on screen, as XCTest wrote it:"] + raw.prefix(mostElements).map { "  \($0)" } + more(raw.count - mostElements)
        case let .read(hierarchy):
            let shown = hierarchy.lines(query: query, most: mostElements)
            guard let query, !shown.found else { return ["on screen:"] + shown.lines.map { "  \($0)" } + more(shown.more) }
            let head = "on screen, nothing the query's \"\(query.text)\" \(query.type) matches:"
            return (screenshot ? [Self.appsOnly, head] : [head]) + shown.lines.map { "  \($0)" } + more(shown.more)
        }
    }

    /// An export's files by the attachment id that names each, its extension dropped.
    static func files(in export: URL) -> [String: URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: export.path)) ?? []
        return Dictionary(names.map { (URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent, export.appending(path: $0)) }) { first, _ in first }
    }

    static func firstLine(_ text: String) -> String {
        String(text.prefix { $0 != "\n" })
    }
}
