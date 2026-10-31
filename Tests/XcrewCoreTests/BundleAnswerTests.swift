import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// `xcresulttool`'s real answers about the test bed's result bundles, kept beside the captures: a failing test's
/// details, a crash's details and its crash log, and a run's summary and test list with a skip and an expected failure.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct BundleAnswerTests {
    @Test func aFailingTestsDetailsGiveItsFileAndLine() throws {
        #expect(ResultBundle.sourceLocation(details: try Raw.file("serial.details.ProbeTests.testFails.json")) == "/testbed/field/Modules/Feature/Tests/ProbeTests.swift:11")
    }

    /// A crash's details attach its crash log and name no place.
    @Test func aCrashsDetailsNameNoPlace() throws {
        #expect(ResultBundle.sourceLocation(details: try Field.file("crash.details.CrashTests.testOutOfRange.json")) == nil)
    }

    /// The crash log's frames down to the test's own, the first with a source file, below the Swift runtime's.
    @Test func aCrashLogGivesTheExceptionAndTheFramesDownToTheTest() throws {
        #expect(ResultBundle.crashSummary(log: try Field.file("crash.ips")) == [
            "crashed: EXC_BREAKPOINT (SIGTRAP)",
            "libswiftCore.dylib  closure #1 in closure #1 in _assertionFailure(_:_:file:line:flags:)",
            "libswiftCore.dylib  _assertionFailure(_:_:file:line:flags:)",
            "libswiftCore.dylib  Array._checkSubscript(_:wasNativeTypeChecked:)",
            "libswiftCore.dylib  Array.subscript.getter",
            "FeatureTests  CrashTests.testOutOfRange()",
        ])
    }

    /// `CrashTests` is declared in `ProbeTests.swift`: the line is the test's own frame's, whatever its file is named.
    @Test func aCrashsLineIsTheTestsOwnFrame() throws {
        #expect(ResultBundle.crashReport(log: try Field.file("crash.ips"), test: TestID(suite: "CrashTests", name: "testOutOfRange"))?.location == "ProbeTests.swift:35")
    }

    @Test func theTestListGivesEachSkippedTestAndWhy() throws {
        let skips = ResultBundle.skippedTests(listing: try Raw.file("serial.tests.json"))
        #expect(skips.map(\.test) == [TestID(suite: "ProbeTests", name: "testSkipped")])
        #expect(skips.first?.skip.reason == "waits for the farewell screen")
    }

    /// Swift Testing's `.disabled` writes its reason after `Test skipped: `, XCTest's `XCTSkip` after `Test skipped - `.
    @Test func aSwiftTestingSkipsReasonComesWithoutItsPrefix() throws {
        #expect(ResultBundle.skippedTests(listing: try Raw.file("shapes.tests.json")).map(\.skip.reason) == ["skipped on purpose"])
    }

    @Test func theTestListNamesEachExpectedFailure() throws {
        #expect(ResultBundle.expectedFailures(listing: try Raw.file("serial.tests.json")) == ["ProbeTests/testExpectedFailure()"])
    }

    /// Without the test list, which API the tests used is unknown, so the note names both.
    @Test func expectedFailuresAreCountedWithTheTrueTotal() throws {
        #expect(ResultBundle.expectedFailuresNote(summary: try Raw.file("serial.summary.json"))
            == "xcrew: 1 test also ran as an expected failure (XCTExpectFailure or withKnownIssue). They count as neither passed nor failed in the result: 5 tests ran in all.")
    }
}
