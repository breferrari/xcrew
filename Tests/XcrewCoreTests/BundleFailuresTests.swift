import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// A failing run's failures from its result bundle, on the test bed's real captures: each shape the bundle reports its
/// own way, its summary, failures, messages and places as the report gives them.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct BundleFailuresTests {
    /// The report on a raw capture, its bundle's reads answered by what `xcresulttool` answered about it.
    static func report(_ name: String, repeated: Bool = false) async throws -> Report {
        let bundle = try Raw.bundle(name)
        var responses: [String: CommandResult] = ["xcrun xcresulttool get test-results tests --path \(bundle) --compact": .init(status: 0, stdout: try Raw.file("\(name).tests.json"))]
        if let summary = try? Raw.file("\(name).summary.json") { responses["xcrun xcresulttool get test-results summary --path \(bundle) --compact"] = .init(status: 0, stdout: summary) }
        return await Report.make(kind: .test, output: try Raw.output(name), home: Captured.home, runner: FakeRunner(responses: responses), repeated: repeated)
    }

    /// The 27.2 capture's test list with its crash filed as the field run filed it: under `System Failures`, as
    /// `xctest (<pid>) encountered an error`.
    static func filedUnderSystemFailures(_ listing: String) -> String {
        listing
            .replacingOccurrences(of: #""name":"AssertCrashTests""#, with: #""name":"System Failures""#)
            .replacingOccurrences(of: #""name":"test_crash()""#, with: #""name":"xctest (80341) encountered an error""#)
            .replacingOccurrences(of: #""nodeIdentifier":"AssertCrashTests/test_crash()""#, with: #""nodeIdentifier":"xctest (80341) encountered an error""#)
    }

    static func lines(_ report: Report) -> [String] {
        [report.detail ?? "-"] + report.failures.map { "\($0.title) | \($0.message) | \($0.where ?? "-")" }
    }

    /// A test plan's configurations run by Swift Testing: the text lists no failure in a shape it can be read in, and the
    /// bundle gives it, the summary naming it as it names a failure the text lists.
    @Test func aFailureTheTextDoesntListIsTheBundles() async throws {
        #expect(Self.lines(try await Self.report("shapes-configurations")) == [
            "1 of 5 failed · ShapesTests/fails",
            #"ShapesTests/fails | Expectation failed: Kit.name == "Other" | ShapesTests.swift:10"#,
        ])
    }

    /// A crashed test is a failure the bundle words as the text does, with no place of its own.
    @Test func aCrashedTestIsTheBundlesFailure() async throws {
        #expect(Self.lines(try await Self.report("system-failure-crash")) == [
            "1 of 1 failed · AssertCrashTests/test_crash",
            "AssertCrashTests/test_crash | Crash: xctest at implicit closure #1 in AssertCrashTests.test_crash() | -",
        ])
    }

    /// A parallel run's clones run its tests: a test failed on one is one failure, the bundle giving its place, which
    /// the text leaves out.
    @Test func aParallelRunsFailureIsOneWithItsPlace() async throws {
        #expect(Self.lines(try await Self.report("parallel")) == [
            "1 of 4 failed · ProbeTests/testFails",
            #"ProbeTests/testFails | XCTAssertEqual failed: ("Kit") is not equal to ("Other") - the name is Kit | ProbeTests.swift:10"#,
        ])
    }

    /// A crash the bundle files under `System Failures`, as a field run on iOS 26.5 had it, is its test's failure once:
    /// the text names the test its message names, and so does the bundle's `xctest (<pid>) encountered an error`. Field
    /// shape, names neutralised: the 27.2 capture's text and test list, each written as that run filed the crash.
    @Test func aCrashFiledUnderSystemFailuresIsItsTestsFailureOnce() async throws {
        let bundle = try Raw.bundle("system-failure-crash")
        let filed = "  ✗ AssertCrashTests / test_crash(): Crash: xctest at implicit closure #1 in AssertCrashTests.test_crash()"
        let text = try Raw.text("system-failure-crash")
        #expect(text.contains(filed))
        let fieldText = text.replacingOccurrences(of: filed, with: "  ✗ System Failures / xctest (80341) encountered an error: Crash: xctest at implicit closure #1 in AssertCrashTests.test_crash()")
        let listing = try Raw.file("system-failure-crash.tests.json")
        #expect(listing.contains(#""name":"AssertCrashTests""#) && listing.contains(#""nodeIdentifier":"AssertCrashTests/test_crash()""#))
        let fieldListing = Self.filedUnderSystemFailures(listing)
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(bundle) --compact": .init(status: 0, stdout: fieldListing)])
        let report = await Report.make(kind: .test, output: ToolOutput(text: fieldText, server: .mobileBuildMCP, isError: true), home: Captured.home, runner: runner)
        #expect(Self.lines(report) == [
            "1 of 1 failed · AssertCrashTests/test_crash",
            "AssertCrashTests/test_crash | Crash: xctest at implicit closure #1 in AssertCrashTests.test_crash() | -",
        ])
        // Its test bundle, from the case the bundle filed it as.
        #expect(report.failures.map(\.target) == ["FeatureTests"])
    }

    /// A crash under `System Failures` whose message names its test without an `in`, as a crash in a test's own body
    /// does, is its test's failure once; one whose message names no test is no test's, and stays the text's own line,
    /// once, out of the ledger. Field shape as above, the message composed.
    @Test(arguments: [
        ("Crash: xctest at AssertCrashTests.test_crash()", ["AssertCrashTests/test_crash | Crash: xctest at AssertCrashTests.test_crash() | -"]),
        ("Crash: xctest at Model.load(from:)", []),
    ])
    func aCrashUnderSystemFailuresIsATestsOnlyWhenItsMessageNamesOne(message: String, tests expected: [String]) async throws {
        let bundle = try Raw.bundle("system-failure-crash")
        let filed = "  ✗ AssertCrashTests / test_crash(): Crash: xctest at implicit closure #1 in AssertCrashTests.test_crash()"
        let fieldText = try Raw.text("system-failure-crash").replacingOccurrences(of: filed, with: "  ✗ System Failures / xctest (80341) encountered an error: \(message)")
        let fieldListing = try Self.filedUnderSystemFailures(Raw.file("system-failure-crash.tests.json"))
            .replacingOccurrences(of: "Crash: xctest at implicit closure #1 in AssertCrashTests.test_crash()", with: message)
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(bundle) --compact": .init(status: 0, stdout: fieldListing)])
        let report = await Report.make(kind: .test, output: ToolOutput(text: fieldText, server: .mobileBuildMCP, isError: true), home: Captured.home, runner: runner)
        #expect(report.failures.filter(\.isTest).map { "\($0.title) | \($0.message) | \($0.where ?? "-")" } == expected)
        // The crash is said once: as its test's failure, or as the text's own line when it names none.
        #expect(report.failures.filter { $0.message == message }.count == 1)
    }

    /// A test the text lists as failed that the bundle counts as passed, as one a retry passed, is no failure, and a
    /// note says the two disagree; the repeated run's note says how its runs went, once.
    @Test func aTestTheTextFailsAndTheBundlePassesIsSaidSo() async throws {
        let notes = try await Self.report("retry", repeated: true).notes
        #expect(notes.filter { $0.contains("ProbeTests/testFlaky") } == [
            "xcrew: across repeated runs: ProbeTests/testFails failed every run, a real failure; ProbeTests/testFlaky is flaky, failing 1 of 2.",
            "xcrew: MobileBuildMCP's result lists as failed a test its result bundle doesn't list among its failures under that name: ProbeTests/testFlaky, which the bundle counts as passed. A test the bundle counts as passed, an expected failure or skipped in every entry, test plan configuration and device is left out of the failures here.",
        ])
    }

    /// A test the text lists as failed that the bundle has no entry for stays a failure, with the text's message, in the
    /// run's order, and the note says the bundle has no entry for it: no record is no sign it passed.
    /// Composed from the retry capture, its text naming the flaky test otherwise.
    @Test func aTestTheTextFailsAndTheBundleDoesntListStaysAFailure() async throws {
        let text = try Raw.text("retry")
        #expect(text.contains("✗ ProbeTests / testFlaky:"))
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(try Raw.bundle("retry")) --compact": .init(status: 0, stdout: try Raw.file("retry.tests.json"))])
        let report = await Report.make(kind: .test, output: ToolOutput(text: text.replacingOccurrences(of: "✗ ProbeTests / testFlaky:", with: "✗ ProbeTests / testGone:"), server: .mobileBuildMCP, isError: true), home: Captured.home, runner: runner)
        #expect(report.failures.filter(\.isTest).map { "\($0.title) | \($0.message)" } == [
            #"ProbeTests/testFails | XCTAssertEqual failed: ("Hello, Ada") is not equal to ("Hi, Ada")"#,
            #"ProbeTests/testGone | XCTAssertEqual failed: ("1") is not equal to ("0") - run 1 is odd"#,
        ])
        #expect(report.notes.filter { $0.contains("MobileBuildMCP's result lists") } == [
            "xcrew: MobileBuildMCP's result lists as failed a test its result bundle doesn't list among its failures under that name: ProbeTests/testGone, which the bundle has no entry for under that name. A test the bundle doesn't count as passed, an expected failure or skipped in every entry, test plan configuration and device stays in the failures here, as MobileBuildMCP gives it.",
        ])
    }

    /// A run whose bundle lists no failed test has a summary that names none, though the text names one the bundle
    /// counts as passed. Composed from the retry capture: its text listing only the test a retry passed, and its test
    /// list with every run passing.
    @Test func theSummaryNamesNoTestTheBundleCountsAsPassed() async throws {
        let failing = """
              ✗ ProbeTests / testFails: XCTAssertEqual failed: ("Hello, Ada") is not equal to ("Hi, Ada")
                /testbed/field/Modules/Feature/Tests/ProbeTests.swift:11


            """
        let text = try Raw.text("retry")
        #expect(text.contains(failing))
        let listing = try Raw.file("retry.tests.json")
        #expect(listing.contains(#""result":"Failed""#))
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(try Raw.bundle("retry")) --compact": .init(status: 0, stdout: listing.replacingOccurrences(of: #""result":"Failed""#, with: #""result":"Passed""#))])
        let report = await Report.make(kind: .test, output: ToolOutput(text: text.replacingOccurrences(of: failing, with: ""), server: .mobileBuildMCP, isError: true), home: Captured.home, runner: runner)
        #expect(report.detail == "1 of 4 failed")
        #expect(report.failures.filter(\.isTest).isEmpty)
        #expect(report.notes.contains("xcrew: MobileBuildMCP's result lists as failed a test its result bundle doesn't list among its failures under that name: ProbeTests/testFlaky, which the bundle counts as passed. A test the bundle counts as passed, an expected failure or skipped in every entry, test plan configuration and device is left out of the failures here."))
    }

    /// With no failed test in the bundle, the summary names the first the text lists that the bundle has no entry for,
    /// never one it records as passed; the note names each with what the bundle records. Composed from the retry
    /// capture: the failing test renamed to one that passed, the flaky one to one not listed.
    @Test func theSummaryNamesAnUnlistedTestNeverAPassedOne() async throws {
        let text = try Raw.text("retry")
        #expect(text.contains("✗ ProbeTests / testFails:") && text.contains("✗ ProbeTests / testFlaky:"))
        let listing = try Raw.file("retry.tests.json").replacingOccurrences(of: #""result":"Failed""#, with: #""result":"Passed""#)
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(try Raw.bundle("retry")) --compact": .init(status: 0, stdout: listing)])
        let output = ToolOutput(text: text.replacingOccurrences(of: "✗ ProbeTests / testFails:", with: "✗ ProbeTests / testPasses:").replacingOccurrences(of: "✗ ProbeTests / testFlaky:", with: "✗ ProbeTests / testGone:"), server: .mobileBuildMCP, isError: true)
        let report = await Report.make(kind: .test, output: output, home: Captured.home, runner: runner)
        #expect(report.detail == "1 of 4 failed · ProbeTests/testGone")
        #expect(report.failures.filter(\.isTest).map(\.title) == ["ProbeTests/testGone"])
        #expect(report.notes.contains("xcrew: MobileBuildMCP's result lists as failed tests its result bundle doesn't list among its failures under that name: ProbeTests/testPasses, which the bundle counts as passed; ProbeTests/testGone, which the bundle has no entry for under that name. A test the bundle counts as passed, an expected failure or skipped in every entry, test plan configuration and device is left out of the failures here. A test the bundle doesn't count as passed, an expected failure or skipped in every entry, test plan configuration and device stays in the failures here, as MobileBuildMCP gives it."))
    }

    /// A test the text lists as failed that the bundle records as `unknown`, as one whose process was killed, stays a
    /// failure: only a pass, a skip or an expected failure clears it. Composed from the retry capture, its passed test
    /// cases recorded `unknown`.
    @Test func aTestTheBundleRecordsAsUnknownStaysAFailure() async throws {
        let passed = #""nodeType":"Test Case","result":"Passed""#
        let listing = try Raw.file("retry.tests.json")
        #expect(listing.contains(passed))
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(try Raw.bundle("retry")) --compact": .init(status: 0, stdout: listing.replacingOccurrences(of: passed, with: #""nodeType":"Test Case","result":"unknown""#))])
        let report = await Report.make(kind: .test, output: ToolOutput(text: try Raw.text("retry"), server: .mobileBuildMCP, isError: true), home: Captured.home, runner: runner)
        #expect(report.failures.filter(\.isTest).map(\.title) == ["ProbeTests/testFails", "ProbeTests/testFlaky"])
        #expect(report.notes.contains("xcrew: MobileBuildMCP's result lists as failed a test its result bundle doesn't list among its failures under that name: ProbeTests/testFlaky, which the bundle records as unknown. A test the bundle doesn't count as passed, an expected failure or skipped in every entry, test plan configuration and device stays in the failures here, as MobileBuildMCP gives it."))
    }

    /// Every test case, test plan configuration and device result the captures' test lists hold is one the report reads: a clearing one, or `Failed` or
    /// `unknown`, the schema's others. A value xcresulttool renames shows up here, not as a skip read as a failure.
    @Test func everyCapturedResultIsOneTheReportReads() throws {
        let folder = Testbed.root.appending(path: "captures/raw")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".tests.json") }
        #expect(!names.isEmpty)
        var found: Set<String> = []
        for name in names {
            for node in TestList(try Raw.file(name)).nodes where ["Test Case", "Test Plan Configuration", "Device"].contains(node["nodeType"] as? String) {
                if let result = node["result"] as? String { found.insert(result) }
            }
        }
        #expect(found.subtracting(["Passed", "Expected Failure", "Skipped", "Failed", "unknown"]).isEmpty, "\(found.sorted())")
        #expect(ResultBundle.clearing.map(\.result) == ["Passed", "Expected Failure", "Skipped"])
        #expect(found.isSuperset(of: ["Passed", "Failed", "Skipped", "Expected Failure"]), "\(found.sorted())")
    }

    /// A nested suite's failed test is looked up under the bundle's id for it, `Outer/Inner/fails()`, which is the only
    /// one xcresulttool answers to, never under the text's `Inner/fails()` (the nested capture's `nested.lookups.json`).
    @Test func aNestedSuitesFailureIsLookedUpUnderTheBundlesID() async throws {
        let bundle = try Raw.bundle("nested")
        let lookups = try #require(try JSONSerialization.jsonObject(with: Data(Raw.file("nested.lookups.json").utf8)) as? [String: [String: Any]])
        #expect(lookups["Outer/Inner/fails()"]?["test-details"] as? Bool == true && lookups["Inner/fails()"]?["test-details"] as? Bool == false)
        var responses: [String: CommandResult] = ["xcrun xcresulttool get test-results tests --path \(bundle) --compact": .init(status: 0, stdout: try Raw.file("nested.tests.json"))]
        for test in ["fails", "flaky", "attaches", "addsNumbers"] {
            responses["xcrun xcresulttool get test-results test-details --test-id Outer/Inner/\(test)() --path \(bundle) --compact"] = .init(status: 0, stdout: try Raw.file("nested.details.Outer.Inner.\(test).json"))
        }
        let runner = RecordingRunner(FakeRunner(responses: responses))
        _ = await Report.make(kind: .test, output: try Raw.output("nested"), home: Captured.home, runner: runner)
        let details = runner.asked.filter { $0.contains("test-details") }
        #expect(!details.isEmpty)
        #expect(details.allSatisfy { $0.contains("--test-id Outer/Inner/") }, "\(details)")
    }

    /// A nested suite's failed test has the images xcresulttool exports under the bundle's id for it, kept under that id
    /// for the pane: the nested capture's PNG, which its `attaches()` recorded.
    @Test func aNestedSuitesFailureHasItsImages() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "xcrew-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = try Raw.bundle("nested")
        let attaches = TestID(xcresultID: "Outer/Inner/attaches()")
        let bundle = ResultBundle(path: path, runner: Self.NestedExport(), exportFolder: { root.appending(path: "export-\(UUID().uuidString)") })
        let added = await FailureNotes.adding(to: MobileText(try Raw.text("nested")), from: bundle, keepingImagesIn: (root.appending(path: "images"), Date()),
                                              bundleIDs: [TestID(suite: "Inner", name: "attaches"): .found(attaches)])
        #expect(added?.images[attaches]?.paths.count == 1)
        #expect(added?.text.text.contains("✗ Inner / attaches(): Expectation failed: Kit.name == \"Other\"") == true)
        #expect(added?.text.text.contains("image: ") == true)
    }

    /// A nested suite's test the text lists as failed that the bundle counts as passed under its full id, as one a retry
    /// passed, is no failure, and the note says the bundle counts it as passed. The nested capture, `flaky()`'s case
    /// recorded passed.
    @Test func aNestedSuitesTestTheBundlePassedIsNoFailure() async throws {
        let failed = #""nodeIdentifierURL":"test://com.apple.xcode/SwiftTesting/NestedTests/Outer/Inner/flaky()","nodeType":"Test Case","result":"Failed""#
        let listing = try Raw.file("nested.tests.json")
        #expect(listing.contains(failed))
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(try Raw.bundle("nested")) --compact": .init(status: 0, stdout: listing.replacingOccurrences(of: failed, with: failed.replacingOccurrences(of: #""result":"Failed""#, with: #""result":"Passed""#)))])
        let report = await Report.make(kind: .test, output: try Raw.output("nested"), home: Captured.home, runner: runner)
        #expect(!report.failures.map(\.title).contains { $0.hasSuffix("flaky") }, "\(report.failures.map(\.title))")
        #expect(report.notes.contains { $0.contains("Inner/flaky, which the bundle counts as passed") }, "\(report.notes)")
    }

    /// Each failure the bundle records that the text doesn't list gets its line in the text Claude reads, under Test
    /// Failures, as MobileBuildMCP writes one: the retried nested capture, whose text lists only the display-named
    /// failure from the log.
    @Test func aFailureOnlyTheBundleRecordsIsListedInTheText() async throws {
        let bundle = try Raw.bundle("nested-retry")
        let runner = RecordingRunner(FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(bundle) --compact": .init(status: 0, stdout: try Raw.file("nested-retry.tests.json"))]))
        let report = await Report.make(kind: .test, output: try Raw.output("nested-retry"), home: Captured.home, runner: runner, repeated: true)
        let text = try #require(report.result)
        #expect(text.contains("Test Failures (4):"), "\(text)")
        // With its place as the text writes one, the whole path, so it isn't looked up again.
        #expect(text.contains("✗ Outer / Inner/fails(): Expectation failed: Kit.name == \"Other\"\n    /testbed/swift-testing/NestedTests/NestedTests.swift:8\n"), "\(text)")
        #expect(!runner.asked.contains { $0.contains("test-details --test-id Outer/Inner/fails()") }, "\(runner.asked)")
        #expect(text.contains("✗ Outer / Inner/attaches(): Expectation failed: Kit.name == \"Other\""), "\(text)")
    }

    /// A repeated run's Test Results line for a nested suite's test, named from its own suite, is counted once with
    /// its runs from the bundle, its id resolved by the report. The retried nested capture, its text given the Test
    /// Results `showTestTiming` writes, a line for each of `flaky()`'s two runs (composed).
    @Test func aNestedTestsRunsAreCountedInTheReportsTestResults() async throws {
        let summary = "\n\n❌ 3 tests failed, 4 passed"
        let captured = try Raw.text("nested-retry")
        #expect(captured.contains(summary))
        let timed = captured.replacingOccurrences(of: summary, with: "\n\nTest Results:\n  ❌ Inner/flaky() (0.010s)\n  ✅ Inner/flaky() (0.020s)\(summary)")
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(try Raw.bundle("nested-retry")) --compact": .init(status: 0, stdout: try Raw.file("nested-retry.tests.json"))])
        let report = await Report.make(kind: .test, output: ToolOutput(text: timed, server: .mobileBuildMCP, isError: true), home: Captured.home, runner: runner, repeated: true)
        let text = try #require(report.result)
        #expect(text.contains("Test Results:\n  ❌ Inner/flaky(): failed 1 of 2 runs\n"), "\(text)")
        #expect(!text.contains("Inner/flaky() ("), "\(text)")
    }

    /// The label on a line the bundle's list adds comes right under its place, before the notes looked up for it.
    @Test func theLabelOnAnAddedLineComesBeforeItsNotes() async {
        let text = MobileText("\n🧪 Test\n\nTest Failures (1):\n\n  ✗ Suite / test(): it failed\n    /work/Tests/Suite.swift:4\n\n❌ 1 test failed, 0 passed, 0 skipped (⏱️ 1.0s)")
        let repeated = [ResultBundle.Repeated(test: "Suite/test", failed: 2, passed: 1, runs: 3, verdict: .flaky)]
        let added = await FailureNotes.adding(to: text, from: ResultBundle(path: "/b.xcresult", runner: FakeRunner()), repetitions: repeated,
                                              labels: [TestID(suite: "Suite", name: "test"): "the result bundle's; MobileBuildMCP's text lists it as passed"])
        #expect(added?.text.text.contains("  ✗ Suite / test(): it failed\n    /work/Tests/Suite.swift:4\n      the result bundle's; MobileBuildMCP's text lists it as passed\n      failed 2 of 3 runs\n") == true, "\(added?.text.text ?? "")")
    }

    /// The line added for a test that takes arguments names it as the bundle lists it, with its labels and no `()`
    /// after them: `ShapesTests/parameterised(value:)`, from the test bed's shapes captures.
    @Test func theLineAddedForATestWithArgumentsNamesItAsTheBundleDoes() {
        let text = MobileText("\n🧪 Test\n\n❌ 1 test failed, 0 passed, 0 skipped (⏱️ 1.0s)")
        let added = text.adding(unlisted: [(TestID(xcresultID: "ShapesTests/parameterised(value:)"), "it failed", nil)])
        #expect(added?.text.contains("  ✗ ShapesTests / parameterised(value:): it failed\n") == true, "\(added?.text ?? "")")
    }

    /// A failure only the bundle records, of a test the text lists as passed, is labelled as the bundle's where its line
    /// is added: the two disagree. The timing capture, its Test Results listing `testPasses` passed, and its test list
    /// recording it failed.
    @Test func aFailureOnlyTheBundleRecordsIsLabelledWhereTheTextListsItPassed() async throws {
        let passed = #""nodeIdentifierURL":"test://com.apple.xcode/Feature/FeatureTests/ProbeTests/testPasses","nodeType":"Test Case","result":"Passed""#
        let listing = try Raw.file("timing.tests.json")
        let timing = try Raw.text("timing")
        #expect(listing.contains(passed) && timing.contains("✅ ProbeTests/testPasses (0.000s)"))
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(try Raw.bundle("timing")) --compact": .init(status: 0, stdout: listing.replacingOccurrences(of: passed, with: passed.replacingOccurrences(of: #""result":"Passed""#, with: #""result":"Failed""#)))])
        let report = await Report.make(kind: .test, output: try Raw.output("timing"), home: Captured.home, runner: runner)
        let text = try #require(report.result)
        #expect(text.contains("✗ ProbeTests / testPasses(): \n      the result bundle's; MobileBuildMCP's text lists it as passed\n"), "\(text)")
        #expect(report.failures.first { $0.title == "ProbeTests/testPasses" }?.message == "", "\(report.failures)")
    }

    /// A nested suite's failure only the bundle records, of a test the text lists as passed under the name it gives it,
    /// from its own suite, is labelled as the bundle's: the text's name is found as the bundle's id by the one rule. The
    /// retried nested capture, its text given the Test Results `showTestTiming` writes, `Inner/fails()` passed (composed).
    @Test func aNestedFailureTheTextListsAsPassedIsLabelled() async throws {
        let summary = "\n\n❌ 3 tests failed, 4 passed"
        let captured = try Raw.text("nested-retry")
        #expect(captured.contains(summary))
        let timed = captured.replacingOccurrences(of: summary, with: "\n\nTest Results:\n  ✅ Inner/fails() (0.010s)\(summary)")
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(try Raw.bundle("nested-retry")) --compact": .init(status: 0, stdout: try Raw.file("nested-retry.tests.json"))])
        let report = await Report.make(kind: .test, output: ToolOutput(text: timed, server: .mobileBuildMCP, isError: true), home: Captured.home, runner: runner)
        let text = try #require(report.result)
        #expect(text.contains("✗ Outer / Inner/fails(): Expectation failed: Kit.name == \"Other\"\n    /testbed/swift-testing/NestedTests/NestedTests.swift:8\n      the result bundle's; MobileBuildMCP's text lists it as passed\n"), "\(text)")
    }

    /// A crash filed under `System Failures` whose message names a test in a nested suite is said once: the text's line
    /// names it as the bundle's failure does, from the innermost suite its message names, so no line is added for it.
    /// Field shape as above, the bundle's entry the `xctest (<pid>)` case, the message composed.
    @Test func aCrashUnderSystemFailuresNamingANestedSuitesTestIsSaidOnce() async throws {
        let message = "Crash: xctest at implicit closure #1 in Outer.AssertCrashTests.test_crash()"
        let bundle = try Raw.bundle("system-failure-crash")
        let filed = "  ✗ AssertCrashTests / test_crash(): Crash: xctest at implicit closure #1 in AssertCrashTests.test_crash()"
        let fieldText = try Raw.text("system-failure-crash").replacingOccurrences(of: filed, with: "  ✗ System Failures / xctest (80341) encountered an error: \(message)")
        let fieldListing = try Self.filedUnderSystemFailures(Raw.file("system-failure-crash.tests.json"))
            .replacingOccurrences(of: "Crash: xctest at implicit closure #1 in AssertCrashTests.test_crash()", with: message)
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(bundle) --compact": .init(status: 0, stdout: fieldListing)])
        let report = await Report.make(kind: .test, output: ToolOutput(text: fieldText, server: .mobileBuildMCP, isError: true), home: Captured.home, runner: runner)
        #expect(!(report.result ?? "").contains("✗ AssertCrashTests / test_crash()"), "\(report.result ?? "")")
        #expect(report.failures.filter(\.isTest).map(\.title) == ["AssertCrashTests/test_crash"])
    }

    /// A crash the bundle files under `System Failures` that the text doesn't list gets its line, and is looked up under
    /// the bundle's id for it, its `xctest (<pid>)` case, the one xcresulttool knows. Field shape as above, the text's
    /// line for the crash left out.
    @Test func aCrashUnderSystemFailuresTheTextLeavesOutIsLookedUpUnderItsCase() async throws {
        let bundle = try Raw.bundle("system-failure-crash")
        let filed = "  ✗ AssertCrashTests / test_crash(): Crash: xctest at implicit closure #1 in AssertCrashTests.test_crash()\n"
        let text = try Raw.text("system-failure-crash")
        #expect(text.contains(filed))
        let runner = RecordingRunner(FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(bundle) --compact": .init(status: 0, stdout: try Self.filedUnderSystemFailures(Raw.file("system-failure-crash.tests.json")))]))
        let report = await Report.make(kind: .test, output: ToolOutput(text: text.replacingOccurrences(of: filed, with: ""), server: .mobileBuildMCP, isError: true), home: Captured.home, runner: runner)
        #expect((report.result ?? "").contains("✗ AssertCrashTests / test_crash(): Crash: xctest at implicit closure #1 in AssertCrashTests.test_crash()"), "\(report.result ?? "")")
        #expect(runner.asked.contains { $0.hasPrefix("xcrun xcresulttool export attachments") && $0.contains("--test-id xctest (80341) encountered an error --only-failures") }, "\(runner.asked)")
        #expect(!runner.asked.contains { $0.contains("--test-id AssertCrashTests/test_crash()") }, "\(runner.asked)")
    }

    /// A crash the bundle files under `System Failures` that the text names is looked up under the bundle's id for it, its
    /// `xctest (<pid>)` case, the one xcresulttool knows (docs/findings.md, *A crash under System Failures*). Field shape
    /// as above.
    @Test func aCrashUnderSystemFailuresTheTextNamesIsLookedUpUnderItsCase() async throws {
        let bundle = try Raw.bundle("system-failure-crash")
        let filed = "  ✗ AssertCrashTests / test_crash(): Crash: xctest at implicit closure #1 in AssertCrashTests.test_crash()"
        let text = try Raw.text("system-failure-crash").replacingOccurrences(of: filed, with: "  ✗ System Failures / xctest (80341) encountered an error: Crash: xctest at implicit closure #1 in AssertCrashTests.test_crash()")
        let runner = RecordingRunner(FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(bundle) --compact": .init(status: 0, stdout: try Self.filedUnderSystemFailures(Raw.file("system-failure-crash.tests.json")))]))
        _ = await Report.make(kind: .test, output: ToolOutput(text: text, server: .mobileBuildMCP, isError: true), home: Captured.home, runner: runner)
        #expect(runner.asked.contains { $0.hasPrefix("xcrun xcresulttool export attachments") && $0.contains("--test-id xctest (80341) encountered an error --only-failures") }, "\(runner.asked)")
        #expect(!runner.asked.contains { $0.contains("--test-id AssertCrashTests/test_crash()") }, "\(runner.asked)")
    }

    /// A failure the text leaves out is looked up under its own id before a `System Failures` case that names it: the
    /// crash capture's own case, with a crash case naming it added to its test list, its line left out of the text.
    @Test func aFailureTheTextLeavesOutIsLookedUpUnderItsOwnIDFirst() async throws {
        let bundle = try Raw.bundle("system-failure-crash")
        let filed = "  ✗ AssertCrashTests / test_crash(): Crash: xctest at implicit closure #1 in AssertCrashTests.test_crash()\n"
        let text = try Raw.text("system-failure-crash")
        #expect(text.contains(filed))
        let crashCase = #"{"nodeType":"Test Suite","name":"System Failures","children":[{"nodeType":"Test Case","name":"xctest (9) encountered an error","nodeIdentifier":"xctest (9) encountered an error","result":"Failed","children":[{"nodeType":"Failure Message","name":"Crash: xctest at AssertCrashTests.test_crash()"}]}]},"#
        let listing = try Raw.file("system-failure-crash.tests.json")
        #expect(listing.contains(#""testNodes":["#))
        let runner = RecordingRunner(FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(bundle) --compact": .init(status: 0, stdout: listing.replacingOccurrences(of: #""testNodes":["#, with: #""testNodes":["# + crashCase))]))
        _ = await Report.make(kind: .test, output: ToolOutput(text: text.replacingOccurrences(of: filed, with: ""), server: .mobileBuildMCP, isError: true), home: Captured.home, runner: runner)
        #expect(runner.asked.contains { $0.contains("--test-id AssertCrashTests/test_crash() --only-failures") }, "\(runner.asked)")
        #expect(!runner.asked.contains { $0.contains("--test-id xctest (9) encountered an error") }, "\(runner.asked)")
    }

    /// A repeated run's nested suite's test, named from its own suite in the text, has its runs counted under its line:
    /// the nested capture's text against the retried run's test list, each of `fails()`'s three runs failed.
    @Test func aRepeatedNestedTestHasItsRunsCountedUnderTheTextsName() async throws {
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(try Raw.bundle("nested")) --compact": .init(status: 0, stdout: try Raw.file("nested-retry.tests.json"))])
        let report = await Report.make(kind: .test, output: try Raw.output("nested"), home: Captured.home, runner: runner, repeated: true)
        let text = try #require(report.result)
        #expect(text.contains("✗ Inner / fails(): Expectation failed: Kit.name == \"Other\"\n      failed 3 of 3 runs\n"), "\(text)")
    }

    /// A crashed test the bundle has more than one test by the name of keeps the runtime error the run lists: it's said
    /// under its line though nothing is looked up for it. The timing capture's crash, its name two nested suites'.
    @Test func anAmbiguousCrashedTestKeepsTheRuntimeError() async throws {
        let ambiguous = TestLookup.Resolution.ambiguous([TestID(xcresultID: "A/CrashTests/testOutOfRange()"), TestID(xcresultID: "B/CrashTests/testOutOfRange()")])
        let added = await FailureNotes.adding(to: MobileText(try Raw.text("timing")), from: ResultBundle(path: try Raw.bundle("timing"), runner: FakeRunner()),
                                              bundleIDs: [TestID(suite: "CrashTests", name: "testOutOfRange"): ambiguous])
        #expect(added?.text.text.contains("Fatal error: Index out of range") == true, "\(added?.text.text ?? "")")
    }

    /// What xcresulttool answers about each of the nested capture's failed tests, under the bundle's id and under the
    /// text's name for it: `test-details`, `activities` and `export attachments` answer to the bundle's id alone.
    @Test func xcresulttoolAnswersANestedTestUnderItsFullIDAlone() throws {
        let lookups = try #require(try JSONSerialization.jsonObject(with: Data(Raw.file("nested.lookups.json").utf8)) as? [String: [String: Any]])
        for test in ["fails", "flaky", "attaches", "addsNumbers"] {
            #expect(lookups["Outer/Inner/\(test)()"]?["test-details"] as? Bool == true && lookups["Outer/Inner/\(test)()"]?["activities"] as? Bool == true, "\(test)")
            #expect(lookups["Inner/\(test)()"]?["test-details"] as? Bool == false && lookups["Inner/\(test)()"]?["activities"] as? Bool == false, "\(test)")
            #expect(lookups["Inner/\(test)()"]?["export attachments"] as? String == "none", "\(test)")
        }
        #expect(lookups["Outer/Inner/attaches()"]?["export attachments"] as? Int == 1)
    }

    /// The label on a line the bundle's list adds comes after the place the run's details give it.
    @Test func theLabelOnAnAddedLineComesAfterItsPlace() async throws {
        let passed = #""nodeIdentifierURL":"test://com.apple.xcode/Feature/FeatureTests/ProbeTests/testPasses","nodeType":"Test Case","result":"Passed""#
        let bundle = try Raw.bundle("timing")
        let runner = FakeRunner(responses: [
            "xcrun xcresulttool get test-results tests --path \(bundle) --compact": .init(status: 0, stdout: try Raw.file("timing.tests.json").replacingOccurrences(of: passed, with: passed.replacingOccurrences(of: #""result":"Passed""#, with: #""result":"Failed""#))),
            "xcrun xcresulttool get test-results test-details --test-id ProbeTests/testPasses() --path \(bundle) --compact": .init(status: 0, stdout: try Raw.file("timing.details.ProbeTests.testFails.json")),
        ])
        let report = await Report.make(kind: .test, output: try Raw.output("timing"), home: Captured.home, runner: runner)
        let text = try #require(report.result)
        #expect(text.contains("✗ ProbeTests / testPasses(): \n    /testbed/field/Modules/Feature/Tests/ProbeTests.swift:11\n      the result bundle's; MobileBuildMCP's text lists it as passed\n"), "\(text)")
    }

    /// A failed test the text names that two failed nested tests' ids end with is one of them: each is listed under its
    /// own id, with its own message and place, the text's line goes, and a note on each says what MobileBuildMCP reported.
    /// Two failures read as two. Composed: two suites' `Inner`, the text naming each `Inner / fails()`.
    @Test func aNameTwoFailedNestedTestsShareListsEachOnce() async throws {
        let home = "/testbed/user"
        let bundle = "\(home)/Library/Developer/MobileBuildMCP/workspaces/field-0000/result-bundles/test_sim_1.xcresult"
        let text = """

            🧪 Test

            Test Failures (2):

              ✗ Inner / fails(): one
                A.swift:3

              ✗ Inner / fails(): two
                B.swift:3

            ❌ 2 tests failed, 0 passed, 0 skipped (⏱️ 1.0s)
              └ Files:
                 └── ~/Library/Developer/MobileBuildMCP/workspaces/field-0000/
                     └── result-bundles/test_sim_1.xcresult — Result Bundle

            """
        let cases = ["A", "B"].enumerated().map { index, suite in
            #"{"nodeType":"Test Case","name":"fails()","nodeIdentifier":"\#(suite)/Inner/fails()","result":"Failed","children":[{"nodeType":"Failure Message","name":"\#(index == 0 ? "one" : "two")","sourceLocation":{"filePath":"/work/\#(suite).swift","lineNumber":3}}]}"#
        }
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(bundle) --compact": .init(status: 0, stdout: #"{"testNodes":[\#(cases.joined(separator: ","))]}"#)])
        let report = await Report.make(kind: .test, output: ToolOutput(text: text, server: .mobileBuildMCP, isError: true), home: home, runner: runner)
        let result = try #require(report.result)
        #expect(result.contains("Test Failures (2):"), "\(result)")
        #expect(!result.contains("✗ Inner / fails()"), "\(result)")
        let note = #"      MobileBuildMCP reported "Inner/fails", which matches these 2 tests: A/Inner/fails and B/Inner/fails"#
        #expect(result.contains("  ✗ A / Inner/fails(): one\n    /work/A.swift:3\n\(note)\n"), "\(result)")
        #expect(result.contains("  ✗ B / Inner/fails(): two\n    /work/B.swift:3\n\(note)\n"), "\(result)")
        #expect(report.failures.map(\.title) == ["A/Inner/fails", "B/Inner/fails"], "\(report.failures)")
        #expect(!report.notes.contains { $0.contains("Inner/fails") }, "\(report.notes)")
    }

    /// A name the text gives twice, of which the bundle records only one candidate as failed and the other as `unknown`,
    /// loses no failure: its first line becomes the failed candidate, in its place, and its second keeps the text's data
    /// with the line saying the bundle has more than one test by that name. A failure between them stays where it was.
    @Test func aNameOneOfWhoseCandidatesFailedLosesNoFailure() async throws {
        let home = "/testbed/user"
        let bundle = "\(home)/Library/Developer/MobileBuildMCP/workspaces/field-0000/result-bundles/test_sim_1.xcresult"
        let text = """

            🧪 Test

            Test Failures (3):

              ✗ Inner / fails(): one
                A.swift:3

              ✗ Other / test(): other
                Other.swift:5

              ✗ Inner / fails(): two
                B.swift:3

            ❌ 3 tests failed, 0 passed, 0 skipped (⏱️ 1.0s)
              └ Files:
                 └── ~/Library/Developer/MobileBuildMCP/workspaces/field-0000/
                     └── result-bundles/test_sim_1.xcresult — Result Bundle

            """
        let nodes = [
            #"{"nodeType":"Test Case","name":"fails()","nodeIdentifier":"A/Inner/fails()","result":"Failed","children":[{"nodeType":"Failure Message","name":"one","sourceLocation":{"filePath":"/work/A.swift","lineNumber":3}}]}"#,
            #"{"nodeType":"Test Case","name":"test()","nodeIdentifier":"Other/test()","result":"Failed","children":[{"nodeType":"Failure Message","name":"other","sourceLocation":{"filePath":"/work/Other.swift","lineNumber":5}}]}"#,
            #"{"nodeType":"Test Case","name":"fails()","nodeIdentifier":"B/Inner/fails()","result":"unknown"}"#,
        ]
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(bundle) --compact": .init(status: 0, stdout: #"{"testNodes":[\#(nodes.joined(separator: ","))]}"#)])
        let report = await Report.make(kind: .test, output: ToolOutput(text: text, server: .mobileBuildMCP, isError: true), home: home, runner: runner)
        let result = try #require(report.result)
        let note = #"      MobileBuildMCP reported "Inner/fails", which matches these 2 tests: A/Inner/fails and B/Inner/fails"#
        #expect(result.contains("Test Failures (3):\n\n  ✗ A / Inner/fails(): one\n    /work/A.swift:3\n\(note)\n\n  ✗ Other / test(): other\n"), "\(result)")
        #expect(result.contains("  ✗ Inner / fails(): two\n      the result bundle has more than one test by that name: A/Inner/fails and B/Inner/fails\n    B.swift:3\n"), "\(result)")
        #expect(report.failures.map(\.title) == ["A/Inner/fails", "Other/test", "Inner/fails"], "\(report.failures)")
    }

    /// A name the text gives once, whose candidates both failed, becomes both, the second after the first and the count
    /// raised by one: each failure is listed once.
    @Test func aNameWithMoreFailedCandidatesThanEntriesListsEach() {
        let text = MobileText("\n🧪 Test\n\nTest Failures (2):\n\n  ✗ Inner / fails(): one\n    A.swift:3\n\n  ✗ Other / test(): other\n\n❌ 2 tests failed, 0 passed, 0 skipped (⏱️ 1.0s)")
        let candidates = [(TestID(xcresultID: "A/Inner/fails()"), "one", "/work/A.swift:3"), (TestID(xcresultID: "B/Inner/fails()"), "two", "/work/B.swift:3")].map { (test: $0.0, message: $0.1, place: Optional($0.2)) }
        let replaced = text.replacing(TestID(suite: "Inner", name: "fails"), with: candidates)
        #expect(replaced?.left == 0)
        #expect(replaced?.text.text.contains("Test Failures (3):\n\n  ✗ A / Inner/fails(): one\n    /work/A.swift:3\n\n  ✗ B / Inner/fails(): two\n    /work/B.swift:3\n\n  ✗ Other / test(): other\n") == true, "\(replaced?.text.text ?? "")")
    }

    /// An entry ends at a line it doesn't indent: one the text doesn't read as a failure, right after it with no blank
    /// line between, stays.
    @Test func aReplacedEntryEndsAtALineItDoesntIndent() {
        let text = MobileText("\n🧪 Test\n\nTest Failures (1):\n\n  ✗ Inner / fails(): one\n    A.swift:3\n  ✗ LLVM Profile Error: Failed to write file \"default.profraw\"\n\n❌ 1 test failed, 0 passed, 0 skipped (⏱️ 1.0s)")
        let replaced = text.replacing(TestID(suite: "Inner", name: "fails"), with: [(test: TestID(xcresultID: "A/Inner/fails()"), message: "one", place: nil)])
        #expect(replaced?.text.text.contains("  ✗ A / Inner/fails(): one\n\n  ✗ LLVM Profile Error: Failed to write file \"default.profraw\"\n") == true, "\(replaced?.text.text ?? "")")
    }

    /// A failed test the text names that ends two of the bundle's nested ids is looked up under neither: its line says the
    /// bundle has more than one test by that name. The nested capture's text, its `Inner` composed into two suites.
    @Test func aNameTwoNestedSuitesShareIsLookedUpUnderNeither() async throws {
        let runner = RecordingRunner(FakeRunner())
        let ambiguous = TestLookup.Resolution.ambiguous([TestID(xcresultID: "A/Inner/fails()"), TestID(xcresultID: "B/Inner/fails()")])
        let added = await FailureNotes.adding(to: MobileText(try Raw.text("nested")), from: ResultBundle(path: try Raw.bundle("nested"), runner: runner),
                                              keepingImagesIn: (FileManager.default.temporaryDirectory.appending(path: "xcrew-tests-\(UUID().uuidString)"), Date()),
                                              bundleIDs: [TestID(suite: "Inner", name: "fails"): ambiguous])
        #expect(added?.text.text.contains("""
              ✗ Inner / fails(): Expectation failed: Kit.name == "Other"
                  the result bundle has more than one test by that name: A/Inner/fails and B/Inner/fails
                Kit.name → "Kit": the name is Kit
            """) == true, "\(added?.text.text ?? "")")
        #expect(!runner.asked.contains { $0.contains("A/Inner/fails()") || $0.contains("B/Inner/fails()") || $0.contains("--test-id Inner/fails()") }, "\(runner.asked)")
    }

    /// `xcresulttool export attachments` as the nested capture's bundle answers it: what it wrote for `attaches()` under
    /// its full id, and nothing under any other (`nested.lookups.json`).
    final class NestedExport: CommandRunning {
        func run(_ argv: [String], stdin: Data?) async -> CommandResult {
            guard argv.contains("export"), let at = argv.firstIndex(of: "--test-id"), argv[at + 1] == "Outer/Inner/attaches()",
                  let out = argv.firstIndex(of: "--output-path") else { return .init(status: 1) }
            try? FileManager.default.removeItem(atPath: argv[out + 1])
            try? FileManager.default.copyItem(at: Testbed.root.appending(path: "captures/raw/nested-attachments"), to: URL(fileURLWithPath: argv[out + 1]))
            return .init(status: 0)
        }
        func which(_ name: String) -> String? { nil }
    }

    /// An expected failure is no failure, nor is a test a retry passed.
    @Test func anExpectedFailureOrARetryThatPassedIsNoFailure() async throws {
        #expect(try await Self.report("serial").failures.map(\.title) == ["ProbeTests/testFails", "ProbeTests/testFlaky"])
        #expect(try await Self.report("retry", repeated: true).failures.map(\.title) == ["ProbeTests/testFails"])
    }
}
