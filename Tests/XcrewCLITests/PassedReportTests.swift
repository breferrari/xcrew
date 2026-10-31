import Foundation
import Testing
import XcrewCore
import XcrewTestSupport

/// `xcrew report --passed`: the mod asks for a run's passed tests only while its ledger has a red waiting.
@Suite struct PassedReportTests {
    static let xcodePassed = #"{"counts":{"failed":0,"passed":1,"total":1},"results":[{"identifier":"PlainTests/testAddition()","state":"Passed"}]}"#

    @Test func reportListsPassedTestsWhenAsked() async throws {
        let run = await Run("report", "--server", "xcode", "--kind", "test", "--passed", stdin: Self.xcodePassed)
        let report = try BackgroundReportTests.json(run)
        let passed = try #require(report["passed"] as? [[String: Any]])
        #expect(passed.map { $0["test"] as? String } == ["PlainTests/testAddition"])
    }

    @Test func reportListsNoPassedTestsUnlessAsked() async throws {
        let run = await Run("report", "--server", "xcode", "--kind", "test", stdin: Self.xcodePassed)
        #expect(try BackgroundReportTests.json(run)["passed"] == nil)
    }
}
