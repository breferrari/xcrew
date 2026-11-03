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
