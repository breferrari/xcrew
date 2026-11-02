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

    /// A warning in a line the branch changed stays listed in the saved result Claude reads; the rest are counted, with
    /// the saved file named.
    @Test func aSavedResultKeepsTheWarningsInChangedLines() async throws {
        let project = Project.temporary(containing: ["Modules/Feature/Sources"])
        let root = ProjectLayout.canonical(project.root)
        let json = try Self.json().replacingOccurrences(of: "/testbed/field", with: root)
        let saved = SavedResultTests.saved(json)
        let runner = FakeRunner(responses: FakeRunner.branch(at: project.root, changed: ["Modules/Feature/Sources/Legacy7.swift"], diffed: ["\(root)/Modules/Feature/Sources/Legacy7.swift"], diff: "+++ Modules/Feature/Sources/Legacy7.swift\n@@ -2,0 +3 @@\n"))
        let report = await Report.make(kind: .test, output: ToolOutput(text: Self.notice(saved), server: .mobileBuildMCP), home: Captured.home, runner: runner, project: project)
        let result = try #require(report.result, "no shorter result")
        let diagnostics = try #require(((ResultBundle.parse(result) as? [String: Any])?["data"] as? [String: Any])?["diagnostics"] as? [String: Any])
        let kept = try #require(diagnostics["warnings"] as? [[String: String]])
        #expect(kept.map { $0["location"] } == ["\(root)/Modules/Feature/Sources/Legacy7.swift:3"])
        #expect(diagnostics["warningsLeftOut"] as? String == "353 warnings outside the lines this branch changed left out; the full list is in \(saved)")
    }

    /// The test bed's `concurrency` build text, saved as Claude Code saves a large result, its paths moved under a
    /// temporary project whose branch changed `Kit/Kit.swift` at line 13, with `filler` lines that aren't warnings added.
    static func savedText(filler: Int) async throws -> Report {
        let project = Project.temporary(containing: ["Kit"])
        let root = ProjectLayout.canonical(project.root)
        let text = try Raw.text("build_sim").replacingOccurrences(of: "/testbed/concurrency", with: root)
        let saved = SavedResultTests.saved(text + String(repeating: "   Compiling one of the app's many source files, a line that isn't a warning, to make it long.\n", count: filler))
        let runner = FakeRunner(responses: FakeRunner.branch(at: project.root, changed: ["Kit/Kit.swift"], diffed: ["\(root)/Kit/Kit.swift"], diff: "+++ Kit/Kit.swift\n@@ -12,0 +13 @@\n"))
        let notice = "Error: result (57,000 characters) exceeds maximum allowed tokens. Output has been saved to \(saved).\nFormat: Text"
        return await Report.make(kind: .build, output: ToolOutput(text: notice, server: .mobileBuildMCP), home: Captured.home, runner: runner, project: project)
    }

    /// A saved text result whose bulk isn't warnings stays saved when its warnings are left out: what's left, 600 lines of
    /// 95 characters, 57,000, is still past the 50,000 characters at which Claude Code saves a text result (docs/findings.md).
    @Test func aSavedTextStillLongWithoutItsWarningsStaysSaved() async throws {
        let report = try await Self.savedText(filler: 600)
        #expect(report.result == nil)
    }

    /// One short once its warnings are left out comes back in the notice's place, with the warning in a changed line.
    @Test func aSavedTextShortWithoutItsWarningsComesBack() async throws {
        let result = try #require(try await Self.savedText(filler: 0).result)
        #expect(result.contains("Kit/Kit.swift:13"))
        #expect(result.contains("left out"))
    }

    /// Any of xcrew's edits keeps a saved text saved while it's still that long: here the coverage runtime's error left out
    /// of a failed test run, 600 lines of 95 characters after it.
    @Test func aSavedTextEditedOtherwiseStaysSavedWhileItsLong() async {
        let text = "🧪 Test\n\nErrors (2):\n\n  ✗ Build failed: linker error\n  ✗ LLVM Profile Error: Failed to write file \"default.profraw\": Operation not permitted\n\n"
        let saved = SavedResultTests.saved(text + String(repeating: "   Compiling one of the app's many source files, a line that isn't a warning, to make it long.\n", count: 600))
        let notice = "Error: result (57,000 characters) exceeds maximum allowed tokens. Output has been saved to \(saved).\nFormat: Text"
        let report = await Report.make(kind: .test, output: ToolOutput(text: notice, server: .mobileBuildMCP, isError: true), home: Captured.home, runner: FakeRunner())
        #expect(report.result == nil)
    }

    /// A saved result still long once compacted stays saved too: its errors, which compacting never leaves out, are 600 of
    /// about 100 characters each, past the 50,000 at which Claude Code saves a result.
    @Test func aSavedResultStillLongOnceCompactedStaysSaved() async throws {
        let errors = (1...600).map { index in ["message": "cannot find 'Greeting\(index)' in scope, so this line of the build's error list runs on", "location": "/testbed/field/Modules/Feature/Sources/Feature\(index).swift:7"] }
        let saved = SavedResultTests.saved(try Self.json(errors: errors))
        let report = await Report.make(kind: .test, output: ToolOutput(text: Self.notice(saved), server: .mobileBuildMCP), home: Captured.home, runner: FakeRunner())
        #expect(report.result == nil)
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
