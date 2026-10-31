import Foundation
import Testing
@testable import XcrewCLI
import XcrewCore
import XcrewTestSupport

/// MobileBuildMCP's text for a run whose filter matched no test says only "Test succeeded": no test ran, which is a fact,
/// not a pass. A passing run that ran tests counts them.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedEmptyFilterTests {
    static func report(_ capture: String) async throws -> Report {
        let text = try String(contentsOf: Testbed.root.appending(path: "captures/field/\(capture)"), encoding: .utf8)
        return await Report.make(kind: .test, output: ToolOutput(text: text, server: .mobileBuildMCP), home: "/testbed/user", runner: FakeRunner())
    }

    @Test func aFilterThatMatchedNoTestRanNone() async throws {
        let report = try await Self.report("empty-filter.txt")
        #expect(!report.ok)
        #expect(report.detail == "no tests ran")
        #expect(report.tests == 0)
        #expect(report.notes.contains(Report.noTestsNote))
    }

    @Test func aPassingRunThatRanTestsIsAPass() async throws {
        let report = try await Self.report("coverage.txt")
        #expect(report.ok)
        #expect(report.detail != "no tests ran")
    }
}
