import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// MobileBuildMCP's real results for a passing test run, a passing build and a run matching no test, each read as the text
/// Claude Code hands the mod and as the JSON MobileBuildMCP returns beside it.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct RawResultTests {
    static let bundle = "/Users/dev/Library/Developer/MobileBuildMCP/workspaces/field-3d32f8cd53a2/result-bundles/test_sim_2026-10-31T02-58-52-105Z_pid20279_8eddb088.xcresult"

    @Test func aPassingTestRunGivesItsCountAndNoFailuresEitherWay() {
        for output in [Raw.output("swift-testing"), Raw.jsonOutput("swift-testing")] {
            #expect(output.summary == .init(ok: true, detail: "1 passed"))
            #expect(output.testTotal == 1)
            #expect(output.failures.isEmpty)
        }
    }

    @Test func aPassingBuildIsASuccessWithNoCountEitherWay() {
        for output in [Raw.output("build_sim"), Raw.jsonOutput("build_sim")] {
            #expect(output.summary == .init(ok: true))
            #expect(output.testTotal == nil)
            #expect(output.failures.isEmpty)
        }
    }

    /// The text rounds to a tenth of a second; the JSON gives the milliseconds.
    @Test func eachShapeSaysHowLongTheRunItselfTook() {
        #expect(Raw.output("swift-testing").reportedDuration == 7_200)
        #expect(Raw.jsonOutput("swift-testing").reportedDuration == 7_249)
    }

    @Test func aRunMatchingNoTestIsNoSuccessInItsJSON() {
        #expect(Raw.jsonOutput("empty-filter").summary == .init(ok: false, detail: "no tests ran"))
    }

    @Test func aRunMatchingNoTestTellsClaudeWhyFromItsJSON() async {
        let report = await Report.make(kind: .test, output: Raw.jsonOutput("empty-filter"), home: Captured.home, runner: FakeRunner())
        #expect(report.notes == [Report.noTestsNote])
    }

    @Test func theBundleIsFoundInTheJSON() {
        #expect(ResultBundle.path(in: Raw.jsonOutput("swift-testing"), home: Captured.home) == Self.bundle)
    }

    @Test func aPassingRunKeepsTheServersResultEitherWay() async {
        for (output, duration) in [(Raw.output("swift-testing"), 7_200), (Raw.jsonOutput("swift-testing"), 7_249)] {
            let report = await Report.make(kind: .test, output: output, home: Captured.home, runner: FakeRunner())
            #expect(report == Report(ok: true, detail: "1 passed", durationMs: duration, tests: 1, failures: [], result: nil, notes: [], bundle: Self.bundle))
        }
    }

    @Test func aLeftOutListIsPointedToWithoutACountOfItsOwn() throws {
        let compact = try #require(Raw.jsonOutput("serial").compactTestResult(savedPath: "/saved.txt"))
        let json = try #require((ResultBundle.parse(compact) as? [String: Any])?["data"] as? [String: Any])
        #expect(json["testCases"] as? String == "per-test list left out to keep this result short; the counts above are complete, and the full result is in /saved.txt")
        #expect(Raw.jsonOutput("build_sim").compactTestResult(savedPath: "/saved.txt") == nil)
    }

    @Test func expectedFailuresReachClaudeAsANote() async {
        let runner = FakeRunner(responses: [
            "xcrun xcresulttool get test-results summary --path \(Self.bundle) --compact": .init(status: 0, stdout: Captured.text("xcresultSummaryWithExpectedFailures")),
        ])
        let report = await Report.make(kind: .test, output: Raw.output("swift-testing"), home: Captured.home, runner: runner)
        #expect(report.notes.first?.hasPrefix("xcrew: 2 tests also ran as expected failures") == true)
    }
}
