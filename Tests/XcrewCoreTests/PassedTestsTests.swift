import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// The tests a run's results list as passed, which the ledger turns a red test green from: read only when asked, from
/// the result bundle's test list or the Xcode MCP's results, never inferred from what the run selected.
@Suite struct PassedTestsTests {
    static let bundle = "\(Captured.workspace)/result-bundles/test_sim.xcresult"
    static let listingCommand = "xcrun xcresulttool get test-results tests --path \(bundle) --compact"

    /// MobileBuildMCP's text for a passing run of two tests, naming its result bundle.
    static let passing = "\n🧪 Test\n\n✅ 2 tests passed, 0 failed, 0 skipped (⏱️ 4.4s)\n  └ Files:\n     └── ~/Library/Developer/MobileBuildMCP/workspaces/sample-0000/\n         ├── logs/test_sim.log — Build Logs\n         └── result-bundles/test_sim.xcresult — Result Bundle\n"

    static func testBundle(_ name: String, _ cases: [(String, String)]) -> String {
        let nodes = cases.map { #"{"nodeType":"Test Case","nodeIdentifier":"\#($0.0)","result":"\#($0.1)"}"# }
        return #"{"nodeType":"Unit test bundle","name":"\#(name)","children":[{"nodeType":"Test Suite","name":"Suite","children":[\#(nodes.joined(separator: ","))]}]}"#
    }

    static func listing(_ bundles: [String]) -> String {
        #"{"testNodes":[{"nodeType":"Test Plan","children":[\#(bundles.joined(separator: ","))]}]}"#
    }

    static func report(listing: String?, passed: Bool = true, runner: RecordingRunner? = nil) async -> Report {
        let runner = runner ?? RecordingRunner(FakeRunner(responses: listing.map { [listingCommand: .init(status: 0, stdout: $0)] } ?? [:]))
        return await Report.make(kind: .test, output: ToolOutput(text: passing, server: .mobileBuildMCP), home: Captured.home, runner: runner, listsPassed: passed)
    }

    @Test func aPassingRunListsItsPassedTestsWithTheirTargetWhenAsked() async {
        let report = await Self.report(listing: Self.listing([Self.testBundle("AppTests", [("ViewModelTests/testSave()", "Passed"), ("ViewModelTests/testLoad()", "Passed"), ("ViewModelTests/testSkip()", "Skipped")])]))
        #expect(report.passed == [PassedTest(test: "ViewModelTests/testLoad", target: "AppTests"), PassedTest(test: "ViewModelTests/testSave", target: "AppTests")])
    }

    @Test func aTestOfOneNameIsListedOncePerTargetItPassedIn() async {
        let report = await Self.report(listing: Self.listing([Self.testBundle("FeatureATests", [("ViewModelTests/testLoad()", "Passed")]), Self.testBundle("FeatureBTests", [("ViewModelTests/testLoad()", "Passed")])]))
        #expect(report.passed == [PassedTest(test: "ViewModelTests/testLoad", target: "FeatureATests"), PassedTest(test: "ViewModelTests/testLoad", target: "FeatureBTests")])
    }

    /// As MobileBuildMCP counts it: a test of the same id that failed in another target isn't a pass.
    @Test func aTestThatFailedInAnotherTargetIsNotListed() async {
        let report = await Self.report(listing: Self.listing([Self.testBundle("FeatureATests", [("ViewModelTests/testLoad()", "Passed")]), Self.testBundle("FeatureBTests", [("ViewModelTests/testLoad()", "Failed")])]))
        #expect(report.passed == [])
    }

    @Test func aTestCaseOutsideAnyTestBundleIsListedWithoutATarget() async {
        let report = await Self.report(listing: #"{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"CrashTests/testInRange()","result":"Passed"}]}"#)
        #expect(report.passed == [PassedTest(test: "CrashTests/testInRange", target: nil)])
    }

    @Test func aRunNotAskedForItsPassesReadsNoTestList() async {
        let runner = RecordingRunner(FakeRunner(responses: [Self.listingCommand: .init(status: 0, stdout: Self.listing([]))]))
        let report = await Self.report(listing: nil, passed: false, runner: runner)
        #expect(report.passed == nil)
        #expect(!runner.asked.contains { $0.contains("get test-results tests") }, "\(runner.asked)")
    }

    @Test func aListingThatCantBeReadLeavesPassedAbsent() async {
        #expect(await Self.report(listing: nil).passed == nil)
        #expect(await Self.report(listing: "not json").passed == nil)
    }

    @Test func anXcodeRunListsTheResultsItGivesAsPassed() async {
        let report = await Report.make(kind: .test, output: Captured.output("xcodeTestsPassed"), home: Captured.home, runner: FakeRunner(), listsPassed: true)
        #expect(report.passed == [
            PassedTest(test: "MacroProbeTests/testMacro", target: nil),
            PassedTest(test: "MacroProbeTests/testMacroWithStringLiteral", target: nil),
            PassedTest(test: "PlainTests/testAddition", target: nil),
            PassedTest(test: "PlainTests/testComparison", target: nil),
            PassedTest(test: "PlainTests/testConcatenation", target: nil),
        ])
    }

    @Test func aFailingXcodeRunListsOnlyItsPasses() async {
        let report = await Report.make(kind: .test, output: Captured.output("xcodeTestsFailed"), home: Captured.home, runner: FakeRunner(), listsPassed: true)
        #expect(report.passed == [PassedTest(test: "PlainTests/testAddition", target: nil), PassedTest(test: "PlainTests/testComparison", target: nil)])
    }

    @Test func aRunReadFromItsLogListsItsPassedTests() async {
        let log = "** TEST EXECUTE SUCCEEDED **\n\nTest session results, code coverage, and logs:\n\t\(Self.bundle)\n"
        let runner = FakeRunner(responses: [Self.listingCommand: .init(status: 0, stdout: Self.listing([Self.testBundle("AppTests", [("ViewModelTests/testLoad()", "Passed")])]))])
        let report = await Report.make(kind: .test, log: log, runner: runner, listsPassed: true)
        #expect(report.passed == [PassedTest(test: "ViewModelTests/testLoad", target: "AppTests")])
    }
}

@Suite struct PassedTestsFromANotificationTests {
    /// A backgrounded run's result, read from its task's notification, lists its passed tests as a foreground one does.
    @Test func aRunReadFromItsNotificationListsItsPassedTests() async {
        let text = "<task-notification>\n<task-id>k4q5tm9v2</task-id>\n<status>completed</status>\n<summary>MCP task k4q5tm9v2 (plugin:xcrew:MobileBuildMCP/test_sim) completed.</summary>\n<result>\n\(PassedTestsTests.passing)\n</result>\n</task-notification>"
        let runner = FakeRunner(responses: [PassedTestsTests.listingCommand: .init(status: 0, stdout: PassedTestsTests.listing([PassedTestsTests.testBundle("AppTests", [("ViewModelTests/testLoad()", "Passed")])]))])
        let report = await Report.make(kind: .test, notification: text, log: nil, server: .mobileBuildMCP, home: Captured.home, runner: runner, listsPassed: true)
        #expect(report.passed == [PassedTest(test: "ViewModelTests/testLoad", target: "AppTests")])
    }
}
