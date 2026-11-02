import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// A test run moved to the background that failed: MobileBuildMCP returns an error result, so Claude Code marks the task
/// `failed`, and its notification carries the server's whole text. Field shape, names neutralised: two runs on
/// November 2, 2026 (xcrew 0.13.0) came back as "Task failed: 🧪 Test … Warnings (380): ⚠ …", the whole result, with no
/// note. Which tag holds that text isn't known yet: Claude Code 2.1.316's executable has a "Task failed: " prefix beside
/// its MCP task code. So both shapes are read, each composed from the test bed's failing `serial` run, its one warning
/// made 300: the text after "Task failed: " in `<summary>`, and a `<result>` block after a short summary.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct FailedNotificationTests {
    static let warningCount = 300

    /// `serial`'s text with 300 warnings, the field's hundreds.
    static func text() throws -> String {
        let warnings = (1...warningCount).map { "  ⚠ initialization of immutable value 'unused\($0)' was never used; consider replacing with assignment to '_' or removing it [#NoUsage]\n    /testbed/field/Modules/Feature/Sources/Legacy\($0).swift:3" }
        return try Raw.text("serial").replacingOccurrences(of: "Warnings (1):", with: "Warnings (\(warningCount)):")
            .replacingOccurrences(of: "  ⚠ initialization of immutable value 'unused' was never used; consider replacing with assignment to '_' or removing it [#NoUsage]\n    /testbed/field/Modules/Feature/Sources/Legacy.swift:3", with: warnings.joined(separator: "\n"))
    }

    static func inSummary(_ text: String) -> String {
        "<task-notification>\n<task-id>kftef69ug</task-id>\n<status>failed</status>\n<summary>Task failed: \(text)</summary>\n</task-notification>"
    }

    static func inResult(_ text: String) -> String {
        "<task-notification>\n<task-id>kftef69ug</task-id>\n<status>failed</status>\n<summary>MCP task kftef69ug (plugin:xcrew:MobileBuildMCP/test_sim) failed.</summary>\n<result>\n\(text)\n</result>\n</task-notification>"
    }

    /// Read as the same run in the foreground: a failure, its failing tests named, and any result xcrew writes put back
    /// in the notification it came in. Leaving its warnings out is the foreground's rule for every result (#325).
    @Test(arguments: [("summary", 0), ("result", 1)])
    func aFailedRunsNotificationIsReadAsItsResult(shape: String, index: Int) async throws {
        let text = try Self.text()
        let notification = index == 0 ? Self.inSummary(text) : Self.inResult(text)
        let report = await Report.make(kind: .test, notification: notification, log: nil, server: .mobileBuildMCP, home: Captured.home, runner: FakeRunner())
        #expect(report.isUnread != true, "\(shape)")
        #expect(report.ok == false, "\(shape)")
        #expect(report.failures.map(\.title).contains { $0.contains("testFails") }, "\(shape)")
        #expect(report.result.map { $0.hasPrefix("<task-notification>\n<task-id>kftef69ug</task-id>\n<status>failed</status>") } ?? true, "\(shape)")
    }

    /// The shorter text xcrew writes goes where the server's text was, in either shape.
    @Test func aShorterTextGoesWhereTheServersWas() throws {
        let summary = try #require(TaskNotification(Self.inSummary("long")))
        #expect(summary.serverOutput?.text == "long" && summary.serverOutput?.isError == true)
        #expect(summary.replacingResult(with: "short") == Self.inSummary("short"))
        let result = try #require(TaskNotification(Self.inResult("long")))
        #expect(result.serverOutput?.text == "long" && result.serverOutput?.isError == true)
        #expect(result.replacingResult(with: "short") == Self.inResult("short"))
    }

    /// A killed task's notification carries nothing of the server's: it's read from the log, as before.
    @Test func aKilledTaskIsReadFromItsLogAlone() async throws {
        let killed = Self.inSummary(try Self.text()).replacingOccurrences(of: "<status>failed</status>", with: "<status>killed</status>")
        let report = await Report.make(kind: .test, notification: killed, log: nil, server: .mobileBuildMCP, home: Captured.home, runner: FakeRunner())
        #expect(report.result == nil)
        #expect(report.failures.isEmpty)
    }
}
