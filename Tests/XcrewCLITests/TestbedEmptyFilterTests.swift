import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// MobileBuildMCP's text for a run whose filter matched no test says only "Test succeeded", as it does for a run it couldn't
/// count: its result bundle says no test ran, which is a fact, not a pass. A passing run that ran tests counts them.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedEmptyFilterTests {
    /// "Test succeeded" with no count says nothing of how many ran: the run's result bundle counts 0.
    @Test func aFilterThatMatchedNoTestRanNoneByItsBundle() async throws {
        let text = try TestbedFieldTests.captured("empty-filter.txt")
        let bundle = try TestbedFieldTests.bundle(in: text)
        let runner = try TestbedFieldTests.runner("empty-filter", bundle: bundle)
        let report = await Report.make(kind: .test, output: ToolOutput(text: text, server: .mobileBuildMCP), home: TestbedFieldTests.home, runner: runner)
        #expect(!report.ok)
        #expect(report.detail == "no tests ran")
        #expect(report.tests == 0)
        #expect(report.notes.contains(Report.noTestsInBundleNote))
    }
}
