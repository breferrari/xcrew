import Foundation

/// What a run's result bundle adds to a MobileBuildMCP test run: where each failure happened (on
/// parallel simulator clones xcodebuild logs none), a crash's exception and frames, why each skipped
/// test was skipped, the expected failures its counts leave out, and its coverage. One
/// `xcresulttool` or `xccov` call per question, each well under a second.
public struct ResultBundle: Sendable {
    public struct Skip: Sendable, Equatable {
        public let reason: String?
        public let seconds: Double
    }

    public let path: String
    let runner: any CommandRunning
    /// A fresh folder for one export of a test's attachments; tests pass one they have filled.
    let exportFolder: @Sendable () -> URL
    /// The run's test list, which skips and expected failures both read: asked for once, when first needed.
    let listing: Once<String>

    public init(path: String, runner: any CommandRunning, exportFolder: @escaping @Sendable () -> URL = { FileManager.default.temporaryDirectory.appending(path: "xcrew-attachments-\(UUID().uuidString)") }) {
        self.path = path
        self.runner = runner
        self.exportFolder = exportFolder
        listing = Once { await Self.xcresulttool(["get", "test-results", "tests", "--path", path, "--compact"], runner: runner) }
    }

    /// The run's `.xcresult`, from a passing run's JSON or a failing run's text, with `~` expanded.
    public static func path(in output: ToolOutput, home: String) -> String? {
        output.xcresultPath.map { ToolOutput.expandingHome($0, home: home) }
    }

    // MARK: Reading xcresulttool's output

    /// Every node of a JSON value, breadth first.
    static func nodes(_ json: Any?) -> [[String: Any]] {
        var queue: [Any] = json.map { [$0] } ?? []
        var found: [[String: Any]] = []
        // A cursor, not removeFirst: popping the front of an array copies the rest, quadratic over a 1,000-test list.
        var next = 0
        while next < queue.count {
            let node = queue[next]
            next += 1
            if let array = node as? [Any] {
                queue.append(contentsOf: array)
            } else if let object = node as? [String: Any] {
                found.append(object)
                queue.append(contentsOf: object.keys.sorted().compactMap { object[$0] })
            }
        }
        return found
    }

    static func parse(_ text: String) -> Any? {
        try? JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    /// The first source location in `xcresulttool get test-results test-details` output, as `path:line`.
    public static func sourceLocation(details: String) -> String? {
        for node in nodes(parse(details)) {
            if let location = node["sourceLocation"] as? [String: Any], let file = location["filePath"] as? String, let line = location["lineNumber"] as? Int {
                return "\(file):\(line)"
            }
        }
        return nil
    }

    /// Each failed test in `xcresulttool get test-results tests` output, once whatever configurations it failed under,
    /// with its first failure message; nil when the output isn't a listing, as when `xcresulttool` couldn't read the bundle.
    public static func failedTests(listing: String) -> [ToolOutput.Failure]? {
        guard let json = parse(listing) as? [String: Any], json["testNodes"] != nil else { return nil }
        let found = nodes(json)
        let cases = testCases(in: found)
        return failedTests(in: found).map { test in
            let message = cases[test]?.lazy.compactMap { nodes($0["children"]).first { $0["nodeType"] as? String == "Failure Message" }?["name"] as? String }.first
            return ToolOutput.Failure(title: test.shown, message: message ?? "", isTest: true)
        }
    }

    /// What the result bundle writes before a skip's reason: XCTest's `XCTSkip`, or Swift Testing's `.disabled`.
    static let skipPrefixes = ["Test skipped - ", "Test skipped: "]

    /// Each skipped test in `xcresulttool get test-results tests` output, in the listing's order, with why it was
    /// skipped (its message, without the prefix `skipPrefixes` names) and how long it ran.
    public static func skippedTests(listing: String) -> [(test: TestID, skip: Skip)] {
        nodes(parse(listing)).compactMap { node in
            guard node["nodeType"] as? String == "Test Case", node["result"] as? String == "Skipped",
                  let test = (node["nodeIdentifier"] as? String).map(TestID.init(xcresultID:))
            else { return nil }
            // Directly below the test case, or below each of its repetitions in a repeated run.
            let message = nodes(node["children"]).first { $0["nodeType"] as? String == "Skip Message" }?["name"] as? String
            let reason = message.map { message in
                skipPrefixes.first(where: message.hasPrefix).map { String(message.dropFirst($0.count)) } ?? message
            }
            return (test, Skip(reason: reason, seconds: node["durationInSeconds"] as? Double ?? 0))
        }
    }

    /// Each test the run's test list counts passed, as MobileBuildMCP's count does: a retried test that passed on a later
    /// try among them, its earlier failure only in its repetitions. Never one a test of the same id failed in another
    /// target.
    static func passedTests(listing: String) -> Set<TestID> {
        passedTests(in: parse(listing))
    }

    static func passedTests(in json: Any?) -> Set<TestID> {
        var passed: Set<TestID> = [], failed: Set<TestID> = []
        for node in nodes(json) where node["nodeType"] as? String == "Test Case" {
            guard let id = (node["nodeIdentifier"] as? String).map(TestID.init(xcresultID:)) else { continue }
            switch node["result"] as? String {
            case "Passed": passed.insert(id)
            case "Failed": failed.insert(id)
            default: break
            }
        }
        return passed.subtracting(failed)
    }

    /// Each test `passedTests` counts passed, once per test bundle it passed in, the bundle its target, as `Suite/test`; a
    /// test case filed under no bundle has none. Nil when the listing isn't a test list.
    static func passed(listing: String) -> [PassedTest]? {
        guard let json = parse(listing) as? [String: Any], json["testNodes"] != nil else { return nil }
        let bundles = bundles(in: json, result: "Passed")
        return passedTests(in: json).flatMap { id -> [PassedTest] in
            let targets = bundles[id] ?? []
            return targets.isEmpty ? [PassedTest(id)] : targets.map { PassedTest(id, target: $0) }
        }.sorted()
    }

    /// Each failed test's target in `xcresulttool get test-results tests` output: the test bundle it's filed under, a unit
    /// or UI test bundle named as its target is. A test of the same name failing in two bundles has none: the ledger would
    /// trust a guess.
    public static func targets(listing: String) -> [TestID: String] {
        bundles(in: parse(listing), result: "Failed").compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    /// The test bundles each test case of `result` is filed under, by its id.
    static func bundles(in json: Any?, result: String) -> [TestID: Set<String>] {
        var found: [TestID: Set<String>] = [:]
        for bundle in nodes(json) where (bundle["nodeType"] as? String)?.hasSuffix("test bundle") == true {
            guard let name = bundle["name"] as? String else { continue }
            for node in nodes(bundle["children"]) where node["nodeType"] as? String == "Test Case" && node["result"] as? String == result {
                if let id = node["nodeIdentifier"] as? String { found[TestID(xcresultID: id), default: []].insert(name) }
            }
        }
        return found
    }

    /// Frames of the crashed thread shown when none has a source file: enough to reach the test's own code from the crash.
    static let topFrames = 5
    /// Frames shown at most, down to the first with a source file: the test's own, below the runtime's.
    static let mostFrames = 10

    /// A crash log's exception and the top frames of the thread that crashed, as `image  symbol`.
    public static func crashSummary(log: String) -> [String]? {
        crashReport(log: log)?.summary
    }

    /// A crash log's summary, and the test's line: the crashed thread's frame in `test` itself, or without one, its first
    /// frame with a source file of its own, below the runtime's frames.
    static func crashReport(log: String, test: TestID? = nil) -> (summary: [String], location: String?)? {
        guard let newline = log.firstIndex(of: "\n"),
              let report = parse(String(log[log.index(after: newline)...])) as? [String: Any],
              let threads = report["threads"] as? [[String: Any]],
              let faulting = report["faultingThread"] as? Int, threads.indices.contains(faulting),
              let frames = threads[faulting]["frames"] as? [[String: Any]]
        else { return nil }
        let images = report["usedImages"] as? [[String: Any]] ?? []
        let exception = report["exception"] as? [String: Any]
        let crashed = (exception?["type"] as? String).map { type in "crashed: \(type)\((exception?["signal"] as? String).map { " (\($0))" } ?? "")" }
        let named = test.map { "\($0.suite).\($0.name)(" }
        let ownIndex = frames.firstIndex { frame in named.map { (frame["symbol"] as? String)?.contains($0) == true } == true && ownFrame(frame) != nil }
            ?? frames.firstIndex { ownFrame($0) != nil }
        let own = ownIndex.map { min($0 + 1, mostFrames) } ?? topFrames
        let top = frames.prefix(own).map { frame in
            let index = frame["imageIndex"] as? Int ?? -1
            let image = images.indices.contains(index) ? images[index]["name"] as? String ?? "?" : "?"
            return "\(image)  \(frame["symbol"] as? String ?? "?")"
        }
        return ((crashed.map { [$0] } ?? []) + top, ownIndex.flatMap { ownFrame(frames[$0]) })
    }

    /// A frame's `File.swift:12`, when the crash log names a source file of the project's own for it.
    static func ownFrame(_ frame: [String: Any]) -> String? {
        guard let file = frame["sourceFile"] as? String, !file.hasPrefix("/<"), let line = frame["sourceLine"] as? Int else { return nil }
        return "\(ToolOutput.basename(file)):\(line)"
    }

    /// A run's counts as `xcresulttool get test-results summary` gives them; nothing when it gave none.
    static func counts(summary: String) -> TestCounts? {
        guard let summary = parse(summary) as? [String: Any], let total = summary["totalTestCount"] as? Int else { return nil }
        return TestCounts(passed: summary["passedTests"] as? Int, failed: summary["failedTests"] as? Int, skipped: summary["skippedTests"] as? Int, total: total)
    }

    /// How many tests the summary counts as expected failures.
    public static func expectedFailureCount(summary: String) -> Int {
        (parse(summary) as? [String: Any])?["expectedFailures"] as? Int ?? 0
    }

    /// The XCTest tests in `xcresulttool get test-results tests` output that ran as expected failures
    /// (`XCTExpectFailure`), in the listing's order.
    public static func expectedFailures(listing: String) -> [String] {
        expectedFailureNodes(listing).filter { !isSwiftTesting($0) }.compactMap { $0["nodeIdentifier"] as? String }
    }

    /// The Swift Testing tests in the listing that ran with a known issue (`withKnownIssue`), which
    /// `xcresulttool` files as an Expected Failure too, in the listing's order.
    public static func knownIssues(listing: String) -> [String] {
        expectedFailureNodes(listing).filter(isSwiftTesting).compactMap { $0["nodeIdentifier"] as? String }
    }

    static func expectedFailureNodes(_ listing: String) -> [[String: Any]] {
        nodes(parse(listing)).filter { $0["nodeType"] as? String == "Test Case" && $0["result"] as? String == "Expected Failure" }
    }

    /// A Swift Testing test's identifier URL names it, `test://com.apple.xcode/SwiftTesting/KitTests/…`, where
    /// an XCTest test's names its target's path (docs/findings.md, *Known issues and expected failures*).
    static func isSwiftTesting(_ node: [String: Any]) -> Bool {
        (node["nodeIdentifierURL"] as? String)?.contains("/SwiftTesting/") == true
    }

    /// Expected failures named in the note before the rest are counted.
    static let mostNamed = 5

    /// A note naming a run's expected failures, from `xcresulttool get test-results summary` and the
    /// tests the list names, each by the API it used: XCTest's `XCTExpectFailure` (`names`) and Swift
    /// Testing's `withKnownIssue` (`knownIssues`). MobileBuildMCP's counts leave them out, so passed +
    /// failed + skipped falls short of the tests that ran. Nil when there are none.
    public static func expectedFailuresNote(summary: String, names: [String] = [], knownIssues: [String] = []) -> String? {
        let counts = parse(summary) as? [String: Any]
        let expected = expectedFailureCount(summary: summary)
        guard expected > 0 else { return nil }
        let tests: String
        if knownIssues.isEmpty {
            let api = names.isEmpty ? "XCTExpectFailure or withKnownIssue" : "XCTExpectFailure"
            tests = (expected == 1 ? "1 test also ran as an expected failure" : "\(expected) tests also ran as expected failures") + " (\(api))" + listed(names)
        } else if names.isEmpty {
            tests = (expected == 1 ? "1 test also ran with a known issue" : "\(expected) tests also ran with known issues") + " (withKnownIssue)" + listed(knownIssues)
        } else {
            let failures = names.count == 1 ? "an expected failure" : "expected failures", issues = knownIssues.count == 1 ? "a known issue" : "known issues"
            tests = "\(expected) tests also ran expecting a failure: \(joined(names)) as \(failures) (XCTExpectFailure), \(joined(knownIssues)) with \(issues) (withKnownIssue)"
        }
        let total = (counts?["totalTestCount"] as? Int).map { ": \($0) tests ran in all" } ?? ""
        return "xcrew: \(tests). They count as neither passed nor failed in the result\(total)."
    }

    /// `: A, B and C`, or `: A, B, C, D, E and 2 more`; nothing without names.
    static func listed(_ names: [String], separator: String = ", ") -> String {
        names.isEmpty ? "" : ": " + joined(names, separator: separator)
    }

    /// Names one after another, `a, b and c`, a few at most and the rest counted; with `or`, `a, b or c`.
    static func joined(_ names: [String], separator: String = ", ", or: Bool = false) -> String {
        guard let last = names.last else { return "" }
        let conjunction = or ? " or " : " and "
        if names.count > mostNamed { return names.prefix(mostNamed).joined(separator: separator) + conjunction + "\(names.count - mostNamed) more" }
        return names.count == 1 ? last : names.dropLast().joined(separator: separator) + conjunction + last
    }

    // MARK: Asking xcresulttool

    static func xcresulttool(_ arguments: [String], runner: any CommandRunning) async -> String {
        let ran = await runner.run(["xcrun", "xcresulttool"] + arguments, stdin: nil, timeout: .seconds(15))
        return ran.succeeded ? ran.stdout : ""
    }

    func xcresulttool(_ arguments: [String]) async -> String {
        await Self.xcresulttool(arguments, runner: runner)
    }

    /// One test's details.
    public func details(of test: TestID) async -> String {
        await xcresulttool(["get", "test-results", "test-details", "--test-id", test.xcresultID, "--path", path, "--compact"])
    }

    /// Every test the run ran, with its result: `xcresulttool get test-results tests`.
    public func tests() async -> String {
        await listing.value()
    }

    /// The run's skipped tests: MobileBuildMCP's list can leave one out.
    public func skips() async -> [(test: TestID, skip: Skip)] {
        Self.skippedTests(listing: await tests())
    }

    public func summary() async -> String {
        await xcresulttool(["get", "test-results", "summary", "--path", path, "--compact"])
    }

    // MARK: Asking xccov

    /// The files the coverage archive holds, spelled as the build was started; none when the run gathered no coverage,
    /// which the scheme, its test plan or `-enableCodeCoverage YES` turns on.
    func coveredFiles() async -> [String] {
        Self.parse(await xccov(["--file-list", "--json"])) as? [String] ?? []
    }

    /// Each target's files and how many of its lines ran, as `xccov view --report --json` gives them; empty when it can't.
    func coverageReport() async -> String {
        await xccov(["--report", "--json"], archive: false)
    }

    /// One file's line counts, as `xccov` gives them.
    func coverage(of file: String) async -> String {
        await xccov(["--file", file, "--json"])
    }

    func xccov(_ arguments: [String], archive: Bool = true) async -> String {
        let ran = await runner.run(["xcrun", "xccov", "view"] + (archive ? ["--archive"] : []) + arguments + [path], stdin: nil, timeout: .seconds(15))
        return ran.succeeded ? ran.stdout : ""
    }

    /// A test's attachments, exported to a fresh folder that `read` reads before it's removed: every one, or with
    /// `onlyFailures` only those associated with its failure.
    func attachments<T>(of test: TestID, onlyFailures: Bool, _ read: (URL) async -> T) async -> T {
        let folder = exportFolder()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = await xcresulttool(["export", "attachments", "--path", path, "--output-path", folder.path, "--test-id", test.xcresultID] + (onlyFailures ? ["--only-failures"] : []))
        return await read(folder)
    }

    /// The folder a run's kept files go in, under a cache: the bundle's name without `.xcresult`.
    func runFolder(in cache: URL) -> URL {
        cache.appending(path: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
    }

    /// A crash's summary, from the crash log the result bundle attached to the test, and the test's line it names.
    public func crash(of test: TestID) async -> (summary: [String], location: String?)? {
        await attachments(of: test, onlyFailures: true) { Self.crashSummary(in: $0, test: test) }
    }

    /// A crash's summary, from the crash log among a test's exported attachments, and the test's line it names.
    static func crashSummary(in folder: URL, test: TestID? = nil) -> (summary: [String], location: String?)? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        guard let log = names.sorted().first(where: { $0.hasSuffix(".ips") }),
              let text = try? String(contentsOf: folder.appending(path: log), encoding: .utf8)
        else { return nil }
        return crashReport(log: text, test: test)
    }
}

extension ResultBundle {
    /// A test that ran more than once: how many runs failed and passed, of how many, and what that says.
    public struct Repeated: Sendable, Equatable, Codable {
        public let test: String
        public let failed: Int
        public let passed: Int
        public let runs: Int
        public let verdict: Verdict
    }

    /// Flaky when some runs failed and some passed, real when every run failed, passed when every run passed; none when
    /// the runs say neither, as when they were skipped.
    public enum Verdict: String, Sendable, Codable {
        case flaky, real, passed, none
    }

    /// Each test that ran more than once, with its runs counted: a `Test Case` and every `Repetition` below it, under
    /// each of its arguments for a parameterized Swift Testing test, in the listing's order.
    public static func repetitions(listing: String) -> [Repeated] {
        nodes(parse(listing)).compactMap { node in
            guard node["nodeType"] as? String == "Test Case", let id = node["nodeIdentifier"] as? String else { return nil }
            let runs = nodes(node["children"]).filter { $0["nodeType"] as? String == "Repetition" }
            guard runs.count > 1 else { return nil }
            let failed = runs.count { $0["result"] as? String == "Failed" }
            let passed = runs.count { $0["result"] as? String == "Passed" }
            let verdict: Verdict = failed > 0 && passed > 0 ? .flaky : failed == runs.count ? .real : passed == runs.count ? .passed : .none
            return Repeated(test: TestID(xcresultID: id).shown, failed: failed, passed: passed, runs: runs.count, verdict: verdict)
        }
    }

    /// Each repeated test's verdict, for Claude: the flaky and the failing named, a few at most, and the rest counted.
    /// Nil when nothing ran more than once.
    public static func repetitionsNote(_ repeated: [Repeated]) -> String? {
        guard let runs = repeated.first?.runs else { return nil }
        let decisions = repeated.filter { $0.verdict == .flaky || $0.verdict == .real }
        let named = decisions.prefix(mostNamed).map { test in
            test.verdict == .flaky ? "\(test.test) is flaky, failing \(test.failed) of \(test.runs)" : "\(test.test) failed every run, a real failure"
        }
        let unnamed = decisions.count > mostNamed ? ["and \(decisions.count - mostNamed) more flaky or failing"] : []
        let passed = repeated.count { $0.verdict == .passed }
        let undecided = repeated.count { $0.verdict == .none }
        let each = repeated.allSatisfy { $0.runs == runs } ? "across \(runs) runs each" : "across repeated runs"
        let counted = [
            passed > 0 ? "\(passed) \(decisions.isEmpty ? "" : "more ")passed every run" : nil,
            undecided > 0 ? "\(undecided) gave no verdict, skipped or expected to fail" : nil,
        ].compactMap { $0 }
        let head = (named + unnamed).joined(separator: "; ")
        return "xcrew: \(each): " + [head.isEmpty ? nil : head + ".", counted.isEmpty ? nil : counted.joined(separator: "; ") + "."].compactMap { $0 }.joined(separator: " ")
    }

    /// For a run repeated whose result bundle couldn't be read, or held no repetitions.
    static let noRepetitionsNote = "xcrew: this run repeated its tests, but its result bundle couldn't be read, so there's no verdict on which tests are flaky."
}
