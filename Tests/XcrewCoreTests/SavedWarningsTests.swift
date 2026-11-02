import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// A result Claude Code saved for its size, read back as MobileBuildMCP's JSON: a backgrounded run's notification holds
/// only the notice. Field shape, names neutralised: a passing UI run of no tests whose 354 build warnings were 99% of its
/// 119,619 characters. Composed from the test bed's `empty-filter` JSON, its one warning made 354 distinct ones.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct SavedWarningsTests {
    static let warningCount = 354

    /// `empty-filter`'s JSON with 354 warnings and, when given, its errors.
    static func json(errors: [[String: String]] = []) throws -> String {
        var structured = try #require(try Raw.capture("empty-filter")["structuredContent"] as? [String: Any])
        var data = try #require(structured["data"] as? [String: Any])
        var diagnostics = try #require(data["diagnostics"] as? [String: Any])
        diagnostics["warnings"] = (1...warningCount).map { index in
            ["message": "initialization of immutable value 'unused\(index)' was never used; consider replacing with assignment to '_' or removing it [#NoUsage]", "location": "/testbed/field/Modules/Feature/Sources/Legacy\(index).swift:3"]
        }
        diagnostics["errors"] = errors
        data["diagnostics"] = diagnostics
        structured["data"] = data
        return String(decoding: try JSONSerialization.data(withJSONObject: structured, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }

    static func notice(_ path: String) -> String {
        "Error: result (119,619 characters) exceeds maximum allowed tokens. Output has been saved to \(path).\nFormat: JSON"
    }

    static func shortened(_ json: String) async throws -> (data: [String: Any], saved: String) {
        let saved = SavedResultTests.saved(json)
        let report = await Report.make(kind: .test, output: ToolOutput(text: notice(saved), server: .mobileBuildMCP), home: Captured.home, runner: FakeRunner())
        let result = try #require(report.result, "no shorter result")
        return (try #require((ResultBundle.parse(result) as? [String: Any])?["data"] as? [String: Any]), saved)
    }

    /// The warning list is counted and pointed to in the saved file; everything else stays as it came.
    @Test func aSavedResultsWarningsAreCountedAndPointedTo() async throws {
        let (data, saved) = try await Self.shortened(try Self.json())
        let diagnostics = try #require(data["diagnostics"] as? [String: Any])
        #expect(diagnostics["warnings"] as? String == "354 warnings left out to keep this result short; the full result is in \(saved)")
        #expect((data["summary"] as? [String: Any])?["status"] as? String == "SUCCEEDED")
        #expect(data["artifacts"] != nil)
    }

    /// A failed build's errors are what Claude acts on: never left out.
    @Test func errorsAreNeverLeftOut() async throws {
        let errors = [["message": "cannot find 'Greeting' in scope", "location": "/testbed/field/Modules/Feature/Sources/Feature.swift:7"]]
        let (data, _) = try await Self.shortened(try Self.json(errors: errors))
        let diagnostics = try #require(data["diagnostics"] as? [String: Any])
        #expect(diagnostics["errors"] as? [[String: String]] == errors)
    }

    /// A saved file that isn't there, or isn't MobileBuildMCP's JSON, gives no shorter result: Claude reads what came.
    @Test func aSavedFileThatCantBeReadLeavesTheResultAsItCame() async throws {
        for saved in [SavedResultTests.saved("not json"), "/nonexistent/claude/projects/p/s/tool-results/mcp-test_sim-1.txt"] {
            let report = await Report.make(kind: .test, output: ToolOutput(text: Self.notice(saved), server: .mobileBuildMCP), home: Captured.home, runner: FakeRunner())
            #expect(report.result == nil)
        }
    }
}
