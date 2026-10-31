import Foundation
import Testing

@testable import XcrewCore
import XcrewTestSupport

/// A call Claude Code moved to the background: the handle it answers with names the task, and the task's notification
/// carries the result. Both texts are Claude Code's and undocumented; the fixtures are what Claude Code 2.1.314 sent
/// (docs/findings.md, *A call moved to the background*), and the weekly canary checks its templates still read.
@Suite struct BackgroundTaskTests {
    static func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures/Reports"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func report(_ text: String, server: Server = .mobileBuildMCP, kind: Report.Kind = .build, isError: Bool = false) async -> Report {
        await Report.make(kind: kind, output: ToolOutput(text: text, server: server, isError: isError), home: "/home", runner: FakeRunner())
    }

    @Test func aBackgroundedCallNamesItsTask() async throws {
        let handle = try Self.fixture("backgroundedCall")
        #expect(await report(handle).backgroundTask == "k4q5tm9v2")
        #expect(await report(handle, server: .xcode, kind: .test).backgroundTask == "k4q5tm9v2")
    }

    /// The executable's other two wordings of the handle: a call moved so that a message can reach Claude, and a
    /// server-side task, whose own id comes first and isn't Claude Code's.
    @Test(arguments: [
        #"MCP tool "plugin:xcrew:MobileBuildMCP/build_sim" was moved to the background as task b7x2k so that a message that arrived while it was running can reach you; it was not interrupted and keeps running. You can keep working in the meantime."#,
        #"MCP tool "plugin:xcrew:MobileBuildMCP/build_sim" started server-side task srv-41. It was moved to the background as task b7x2k and keeps running on the server; you can keep working in the meantime. "#,
    ])
    func everyWordingNamesItsTask(_ handle: String) async {
        #expect(await report(handle).backgroundTask == "b7x2k")
    }

    @Test func anErrorNamesNoTask() async throws {
        #expect(await report(try Self.fixture("backgroundedCall"), isError: true).backgroundTask == nil)
    }

    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aResultNamesNoTask() async throws {
        #expect(await report(try Raw.text("build_sim")).backgroundTask == nil)
    }

    @Test func aNotificationCarriesItsStatusAndResult() throws {
        let notification = try #require(TaskNotification(try Self.fixture("taskNotification")))
        #expect(notification.status == "completed")
        #expect(notification.result == "PROBE-RESULT-START " + String(repeating: "x", count: 2000) + " PROBE-RESULT-END")
        #expect(TaskNotification("PROBE-RESULT-START") == nil)
    }

    /// Two notifications in one text, as when two tasks end together: each result ends at its own notification's end.
    @Test func aResultEndsWithItsOwnNotification() throws {
        let first = "<task-notification>\n<task-id>a1</task-id>\n<status>completed</status>\n<result>\none\n</result>\n</task-notification>"
        let second = first.replacingOccurrences(of: "a1", with: "b2").replacingOccurrences(of: "one", with: "two")
        let notification = try #require(TaskNotification(first + "\n" + second))
        #expect(notification.result == "one")
        #expect(notification.replacingResult(with: "short") == first.replacingOccurrences(of: "one", with: "short") + "\n" + second)
    }

    /// The result's own text in the notification's place: the shorter result Claude reads keeps the notification around it.
    @Test func aShorterResultKeepsTheNotification() throws {
        let notification = try #require(TaskNotification(try Self.fixture("taskNotification")))
        #expect(notification.replacingResult(with: "short") == """
            <task-notification>
            <task-id>k4q5tm9v2</task-id>
            <status>completed</status>
            <summary>MCP task k4q5tm9v2 (plugin:notifyprobe:slow/wait) completed.</summary>
            <result>
            short
            </result>
            </task-notification>
            """)
    }

    /// A run log's last xcodebuild verdict, and the result bundle it names: what a task with no result to read still says.
    @Test func aRunLogSaysItsOutcomeAndBundle() throws {
        let log = try Self.fixture("mobileTestLogFailed")
        #expect(RunLog.outcome(of: log, kind: .test) == false)
        #expect(RunLog.resultBundle(in: log) == "/work/App/DerivedData/result-bundles/test_sim_2026-10-30T17-11-06-750Z_pid29308_97473835.xcresult")
        #expect(RunLog.outcome(of: "Build settings from command line:\n\n** BUILD SUCCEEDED **\n", kind: .build) == true)
        #expect(RunLog.outcome(of: "CompileSwift normal arm64 App.swift\n", kind: .build) == nil)
    }

    /// A test run's outcome is its tests' verdict: one stopped after building for testing has none yet, and a run
    /// interrupted after an earlier verdict has none either.
    @Test func aRunLogsOutcomeIsItsOwnLastVerdict() {
        #expect(RunLog.outcome(of: "** TEST BUILD SUCCEEDED **\n\nTesting started\n", kind: .test) == nil)
        #expect(RunLog.outcome(of: "** TEST EXECUTE SUCCEEDED **\n\n** BUILD INTERRUPTED **\n", kind: .test) == nil)
        #expect(RunLog.outcome(of: "** BUILD SUCCEEDED **\n\n** BUILD INTERRUPTED **\n", kind: .build) == nil)
        #expect(RunLog.outcome(of: "** TEST BUILD SUCCEEDED **\n\n** TEST SUCCEEDED **\n", kind: .test) == true)
    }
}
