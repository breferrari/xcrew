import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// MobileBuildMCP's real failing test run with `showTestTiming` on (`captures/raw/timing`): it lists each test under
/// `Test Results:`, all but the one that crashed, which counts among the failures and is named in `Test Failures`.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TimingRunTests {
    @Test func aFailingRunGivesItsCountAndFirstFailingTest() throws {
        let output = try Raw.output("timing")
        #expect(output.summary == .init(ok: false, detail: "3 of 5 failed · CrashTests/testOutOfRange"))
        #expect(output.testTotal == 5)
        #expect(output.reportedDuration == 24_200)
    }

    /// The test that crashed, missing from `Test Results:`, is still among the failures, and each failing test is listed
    /// once, though the text writes `testFails` and `testFails()` apart.
    @Test func eachFailingTestIsListedOnceTheCrashedOneIncluded() throws {
        let tests = try Raw.output("timing").failures.filter(\.isTest)
        #expect(tests == [
            .init(title: "CrashTests/testOutOfRange", message: "Crash: xctest at CrashTests.testOutOfRange()", isTest: true),
            .init(title: "ProbeTests/testFails", message: #"XCTAssertEqual failed: ("Hello, Ada") is not equal to ("Hi, Ada")"#, where: "ProbeTests.swift:11", isTest: true),
            .init(title: "ProbeTests/testFlaky", message: #"XCTAssertEqual failed: ("1") is not equal to ("0") - run 1 is odd"#, where: "ProbeTests.swift:19", isTest: true),
        ])
    }

    @Test func theReportNamesTheCrashedTest() async throws {
        let report = await Report.make(kind: .test, output: try Raw.output("timing"), home: Captured.home, runner: FakeRunner())
        #expect(report.detail == "3 of 5 failed · CrashTests/testOutOfRange")
        #expect(report.tests == 5)
        #expect(report.failures.contains { $0.title == "CrashTests/testOutOfRange" && $0.isTest })
    }

    /// The run's log names its verdict and its result bundle, as a task with no result to read still says.
    @Test func itsLogSaysItsOutcomeAndBundle() throws {
        let log = try Raw.file("timing.log")
        #expect(RunLog.outcome(of: log, kind: .test) == false)
        #expect(RunLog.resultBundle(in: log) == "/testbed/user/Library/Developer/MobileBuildMCP/workspaces/field-f9da0a5d070a/result-bundles/test_sim_2026-10-31T04-52-13-599Z_pid35682_3475a406.xcresult")
    }
}
