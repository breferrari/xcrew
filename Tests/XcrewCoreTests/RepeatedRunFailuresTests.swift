import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// A failing run repeated with `-test-iterations`: MobileBuildMCP's text has no Test Failures section, since it reads
/// failure messages only from directly below a test case and a repeated run files them below its repetitions
/// (MobileBuildMCP 2.7.1, `utils/xcresult-test-failures.js:47-63`). With `showTestTiming`, its Test Results list every
/// repetition. Field shape, names neutralised: the coverage runtime's error, the list of each test's five runs, and the
/// counts, over the test bed's real repeated-run bundle tree (`captures/repetitions/tests.json`).
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct RepeatedRunFailuresTests {
    static let home = "/testbed/user"
    static let bundle = "\(home)/Library/Developer/MobileBuildMCP/workspaces/field-0000/result-bundles/test_sim_1.xcresult"

    /// The five runs of each test, in the order a run lists them: the every-other-run test fails its 2nd and 4th.
    static var text: String {
        let runs = (1...5).flatMap { run in
            [
                "  \(run.isMultiple(of: 2) ? "❌" : "✅") RepetitionTests/testFailsEveryOtherRun() (0.00\(run)s)",
                "  ✅ RepetitionTests/testPassesEveryRun() (0.001s)",
                "  ❌ RepetitionTests/testFailsEveryRun() (0.002s)",
            ]
        }
        return """

            🧪 Test

            Errors (1):

              ✗ LLVM Profile Error: Failed to write file "default.profraw": Operation not permitted

            Test Results:
            \(runs.joined(separator: "\n"))

            ❌ 2 tests failed, 1 passed, 0 skipped (⏱️ 45.3s)
              └ Files:
                 └── ~/Library/Developer/MobileBuildMCP/workspaces/field-0000/
                     ├── logs/test_sim_1.log — Build Logs
                     └── result-bundles/test_sim_1.xcresult — Result Bundle

            """
    }

    static func report() async throws -> Report {
        let listing = try String(contentsOf: Testbed.root.appending(path: "captures/repetitions/tests.json"), encoding: .utf8)
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(bundle) --compact": .init(status: 0, stdout: listing)])
        return await Report.make(kind: .test, output: ToolOutput(text: text, server: .mobileBuildMCP, isError: true), home: home, runner: runner, repeated: true)
    }

    /// Each failing test, with its message and place, from its repetitions in the bundle, as MobileBuildMCP words a
    /// message (without `failed - `).
    @Test func eachFailingTestIsListedWithItsMessageAndPlace() async throws {
        let report = try await Self.report()
        let file = "/testbed/captures/repetitions/AppTests/RepetitionTests.swift"
        #expect(report.failures.map(\.title) == ["RepetitionTests/testFailsEveryOtherRun", "RepetitionTests/testFailsEveryRun"])
        #expect(report.failures.map(\.message) == [#"XCTAssertEqual failed: ("1") is not equal to ("0") - fails on every other run"#, "fails on every run"])
        #expect(report.failures.map(\.where) == ["RepetitionTests.swift:16", "RepetitionTests.swift:9"])
        let result = try #require(report.result)
        #expect(result.contains("    \(file):16") && result.contains("    \(file):9"), "\(result)")
        #expect(result.contains("Test Failures (2):"), "\(result)")
        #expect(result.contains("failed 2 of 5 runs") && result.contains("failed 5 of 5 runs"), "\(result)")
    }

    /// Each repeated test is listed once in Test Results, with its runs counted.
    @Test func eachRepeatedTestIsListedOnce() async throws {
        let result = try #require(try await Self.report().result)
        for test in ["testFailsEveryOtherRun", "testPassesEveryRun", "testFailsEveryRun"] {
            #expect(result.components(separatedBy: "\n").filter { $0.contains("RepetitionTests/\(test)()") }.count == 1, "\(result)")
        }
        #expect(result.contains("  ✅ RepetitionTests/testPassesEveryRun(): passed 5 of 5 runs"), "\(result)")
    }

    /// The coverage runtime's error is no error of the run's, in a test run as in a build: its line and its section go.
    @Test func theCoverageRuntimesErrorIsLeftOut() async throws {
        let result = try #require(try await Self.report().result)
        #expect(!result.contains("LLVM Profile Error"), "\(result)")
        #expect(!result.contains("Errors ("), "\(result)")
    }

    /// A failing run that isn't repeated drops it too: the test bed's `serial` capture with the error a field run listed.
    @Test func aPlainFailingRunLeavesTheCoverageRuntimesErrorOut() async throws {
        let text = try Raw.text("serial").replacingOccurrences(of: "🧪 Test\n\n", with: "🧪 Test\n\nErrors (1):\n\n  ✗ LLVM Profile Error: Failed to write file \"default.profraw\": Operation not permitted\n\n")
        #expect(text.contains("LLVM Profile Error"))
        let report = await Report.make(kind: .test, output: ToolOutput(text: text, server: .mobileBuildMCP, isError: true), home: Captured.home, runner: FakeRunner())
        let result = try #require(report.result)
        #expect(!result.contains("LLVM Profile Error") && !result.contains("Errors ("), "\(result)")
    }
}
