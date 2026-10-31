import Foundation
import Testing
@testable import XcrewCLI
import XcrewCore
import XcrewTestSupport

/// A passing MobileBuildMCP test run's text counts its tests on its `✅` line, which Claude Code hands xcrew in place of the
/// JSON: the outcome says how many passed, and the count is the run's total, as the JSON path gives them.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedPassingCountsTests {
    @Test func aPassingRunsTextGivesItsCountAndTotal() async throws {
        let text = try String(contentsOf: Testbed.root.appending(path: "captures/field/coverage.txt"), encoding: .utf8)
        let report = await Report.make(kind: .test, output: ToolOutput(text: text, server: .mobileBuildMCP), home: "/testbed/user", runner: FakeRunner())
        #expect(report.ok)
        #expect(report.detail == "1 passed")
        #expect(report.tests == 1)
    }
}

/// What the mod reads from `xcrew report` for a passing run, as it calls it: the count the band stores as the next run's
/// "of M", and the outcome's "N passed".
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedPassingReportCommandTests {
    @Test func reportGivesAPassingRunsTestsForTheNextRunsCount() async throws {
        let text = try String(contentsOf: Testbed.root.appending(path: "captures/field/coverage.txt"), encoding: .utf8)
        let run = await Run("report", "--server", "MobileBuildMCP", "--kind", "test", stdin: text)
        let answer = try #require(try JSONSerialization.jsonObject(with: Data(run.text.utf8)) as? [String: Any])
        #expect(answer["tests"] as? Int == 1)
        #expect(answer["detail"] as? String == "1 passed")
    }
}
