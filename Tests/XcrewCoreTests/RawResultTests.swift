import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// MobileBuildMCP's real results for a passing test run, a passing build and a run matching no test, each read as the text
/// Claude Code hands the mod and as the JSON MobileBuildMCP returns beside it.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct RawResultTests {
    static let bundle = Raw.passingBundle

    @Test func aPassingTestRunGivesItsCountAndNoFailuresEitherWay() throws {
        for output in [try Raw.output("swift-testing"), try Raw.jsonOutput("swift-testing")] {
            #expect(output.summary == .init(ok: true, detail: "1 passed"))
            #expect(output.testTotal == 1)
            #expect(output.failures.isEmpty)
        }
    }

    @Test func aPassingBuildIsASuccessWithNoCountEitherWay() throws {
        for output in [try Raw.output("build_sim"), try Raw.jsonOutput("build_sim")] {
            #expect(output.summary == .init(ok: true))
            #expect(output.testTotal == nil)
            #expect(output.failures.isEmpty)
        }
    }

    /// The text rounds to a tenth of a second; the JSON gives the milliseconds.
    @Test func eachShapeSaysHowLongTheRunItselfTook() throws {
        #expect(try Raw.output("swift-testing").reportedDuration == 7_200)
        #expect(try Raw.jsonOutput("swift-testing").reportedDuration == 7_249)
    }

    @Test func aRunMatchingNoTestIsNoSuccessInItsJSON() throws {
        #expect(try Raw.jsonOutput("empty-filter").summary == .init(ok: false, detail: "no tests ran"))
    }

    @Test func aRunMatchingNoTestTellsClaudeWhyFromItsJSON() async throws {
        let report = await Report.make(kind: .test, output: try Raw.jsonOutput("empty-filter"), home: Captured.home, runner: FakeRunner())
        #expect(report.notes == [Report.noTestsNote])
    }

    @Test func theBundleIsFoundInTheJSON() throws {
        #expect(ResultBundle.path(in: try Raw.jsonOutput("swift-testing"), home: Captured.home) == Self.bundle)
    }

    @Test func aPassingRunKeepsTheServersResultEitherWay() async throws {
        for (output, duration) in [(try Raw.output("swift-testing"), 7_200), (try Raw.jsonOutput("swift-testing"), 7_249)] {
            let report = await Report.make(kind: .test, output: output, home: Captured.home, runner: FakeRunner())
            #expect(report == Report(ok: true, detail: "1 passed", durationMs: duration, tests: 1, failures: [], result: nil, notes: [], bundle: Self.bundle))
        }
    }

    @Test func aLeftOutListIsPointedToWithoutACountOfItsOwn() throws {
        let compact = try #require(try Raw.jsonOutput("serial").compactTestResult(savedPath: "/saved.txt"))
        let json = try #require((ResultBundle.parse(compact) as? [String: Any])?["data"] as? [String: Any])
        #expect(json["testCases"] as? String == "per-test list left out to keep this result short; the counts above are complete, and the full result is in /saved.txt")
        #expect(try Raw.jsonOutput("build_sim").compactTestResult(savedPath: "/saved.txt") == nil)
    }
}
