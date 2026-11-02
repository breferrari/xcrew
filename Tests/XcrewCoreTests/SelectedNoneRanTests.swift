import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// A run whose filter matched tests that then didn't execute: MobileBuildMCP lists what its filter selected
/// (`tests.discovered`, and in its text `Discovered N test(s):`, written whatever the run's outcome), and counts 0 run.
/// Field shape, names neutralised: a UI test run filtered to one class, its one test discovered and selected, under a
/// test plan of three configurations, executed 0 tests and reported SUCCEEDED. Composed from the test bed's `empty-filter`
/// capture, its JSON and its zero summary, with the `tests` block and the `Discovered` list in the shape the `shapes`
/// capture gives them.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct SelectedNoneRanTests {
    static let test = "FeatureTests/ProbeTests/testPasses"

    /// The note, with the plan sentence for `Feature`'s three-configuration plan.
    static let planned = "xcrew: this test run executed no tests, though it reports SUCCEEDED and its filter matched 1 test, which MobileBuildMCP lists as discovered: the filter matched, and none executed. Test plan `Feature`, the default of scheme `Feature`, runs each test under each of its configurations: Light, Dark and Large Text."

    /// `empty-filter`'s JSON with the tests its filter selected, as MobileBuildMCP gives them when a filter matches.
    static func json() throws -> String {
        var structured = try #require(try Raw.capture("empty-filter")["structuredContent"] as? [String: Any])
        var data = try #require(structured["data"] as? [String: Any])
        data["tests"] = ["selected": [test], "discovered": ["total": 1, "items": [test]]]
        structured["data"] = data
        return String(decoding: try JSONSerialization.data(withJSONObject: structured, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }

    /// `empty-filter`'s text with the `Discovered` list after its heading, as the `shapes` capture has it.
    static func text() throws -> String {
        let text = try Raw.text("empty-filter")
        let heading = try #require(text.range(of: "🧪 Test\n\n"))
        return text.replacingCharacters(in: heading, with: "🧪 Test\n\nDiscovered 1 test(s):\n   \(test)\n\n")
    }

    /// A project whose scheme `Feature`, which the capture's log names, runs a plan of three configurations, and a home
    /// holding that log where the result names it.
    static func setting() throws -> (project: Project, home: String) {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.writeScheme("Feature", plan: "Feature.xctestplan")
        project.write(#"{"configurations":[{"id":"1","name":"Light","options":{}},{"id":"2","name":"Dark","options":{}},{"id":"3","name":"Large Text","options":{}}],"defaultOptions":{},"testTargets":[],"version":1}"#, to: "Feature.xctestplan")
        let home = project.root.appending(path: "home")
        let log = try #require(ToolOutput(text: try json(), server: .mobileBuildMCP).buildLog(home: home.path))
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: log).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Raw.file("empty-filter.log").write(toFile: log, atomically: true, encoding: .utf8)
        return (project, home.path)
    }

    /// The result Claude Code saved for its size, read back as MobileBuildMCP's JSON, as in the field.
    @Test func aSavedResultWhoseFilterMatchedSaysNoneExecuted() async throws {
        let (project, home) = try Self.setting()
        let report = await Report.make(kind: .test, output: ToolOutput(text: try Self.json(), server: .mobileBuildMCP), home: home, runner: FakeRunner(), project: project)
        #expect(report.detail == "1 selected, none ran")
        #expect(report.ok == false)
        #expect(report.notes == [Self.planned])
    }

    /// The text, whose summary has no count: the result bundle counts 0.
    @Test func aTextWhoseFilterMatchedSaysNoneExecuted() async throws {
        let (project, home) = try Self.setting()
        let output = ToolOutput(text: try Self.text(), server: .mobileBuildMCP)
        let bundle = try #require(ResultBundle.path(in: output, home: home))
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results summary --path \(bundle) --compact": .init(status: 0, stdout: #"{"totalTestCount":0,"passedTests":0,"failedTests":0,"skippedTests":0}"#)])
        let report = await Report.make(kind: .test, output: output, home: home, runner: runner, project: project)
        #expect(report.detail == "1 selected, none ran")
        #expect(report.ok == false)
        #expect(report.notes == [Self.planned])
    }

    /// Without the project, or with a scheme whose plan has one configuration, no plan is named.
    @Test func withoutAPlanOfSeveralConfigurationsNoneIsNamed() async throws {
        let report = await Report.make(kind: .test, output: ToolOutput(text: try Self.json(), server: .mobileBuildMCP), home: "/nonexistent", runner: FakeRunner())
        #expect(report.notes == ["xcrew: this test run executed no tests, though it reports SUCCEEDED and its filter matched 1 test, which MobileBuildMCP lists as discovered: the filter matched, and none executed."])
    }
}
