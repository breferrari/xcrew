import Foundation
import Testing
import XcrewCore
import XcrewTestSupport

/// `xcrew report` for a call Claude Code moved to the background: the task's notification read for its result, and,
/// when it carries none to read, the run's log and the result bundle the log names.
@Suite struct BackgroundReportTests {
    static let failed = #"{"schema":"mobilebuildmcp.output.build-result","data":{"summary":{"status":"FAILED"}}}"#

    /// The notification as Claude Code 2.1.314 words one for an MCP task (docs/findings.md), around `result`.
    static func notification(_ result: String, status: String = "completed") -> String {
        "<task-notification>\n<task-id>k4q5tm9v2</task-id>\n<status>\(status)</status>\n<summary>MCP task k4q5tm9v2 (plugin:xcrew:MobileBuildMCP/build_sim) \(status).</summary>\n<result>\n\(result)\n</result>\n</task-notification>"
    }

    static func json(_ run: Run) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(run.text.utf8)) as? [String: Any])
    }

    @Test func aNotificationIsReadForItsResult() async throws {
        let run = await Run("report", "--server", "MobileBuildMCP", "--kind", "build", "--notification", stdin: Self.notification(Self.failed))
        let report = try Self.json(run)
        #expect(report["ok"] as? Bool == false)
        #expect(report["isUnread"] == nil)
    }

    /// A task killed or failed, or a text that isn't a notification, has no result to read.
    @Test(arguments: [notification("Task failed: the server went away", status: "failed"), notification("", status: "killed"), failed])
    func aNotificationWithoutAResultIsUnread(_ text: String) async throws {
        let run = await Run("report", "--server", "MobileBuildMCP", "--kind", "build", "--notification", stdin: text)
        #expect(try Self.json(run)["isUnread"] as? Bool == true)
    }

    static let bundle = "/work/App/DerivedData/result-bundles/test_sim_2026-10-30T17-11-06-750Z_pid29308_97473835.xcresult"

    static func log(_ verdict: String) throws -> String {
        let log = Project.temporary().root.appending(path: "test_sim.log")
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Test session results, code coverage, and logs:\n\t\(bundle)\n\nFailing tests:\n\tCrashTests.testOutOfRange()\n\n** \(verdict) **\n\nTesting started\n".write(to: log, atomically: true, encoding: .utf8)
        return log.path
    }

    /// The bundle the log names, read by `xcresulttool`, gives each test's result: a test run read as any other.
    @Test func aLogsBundleGivesItsFailingTests() async throws {
        let listing = #"{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"CrashTests/testOutOfRange()","name":"testOutOfRange()","result":"Failed","children":[{"nodeType":"Failure Message","name":"Crash: xctest at CrashTests.testOutOfRange()"}]},{"nodeType":"Test Case","nodeIdentifier":"CrashTests/testInRange()","name":"testInRange()","result":"Passed"}]}"#
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(Self.bundle) --compact": .init(status: 0, stdout: listing)])
        let run = await Run("report", "--server", "MobileBuildMCP", "--kind", "test", "--log", try Self.log("TEST EXECUTE FAILED"), context: .fake(runner))
        let report = try Self.json(run)
        #expect(report["ok"] as? Bool == false)
        #expect(report["bundle"] as? String == Self.bundle)
        let failures = try #require(report["failures"] as? [[String: Any]])
        #expect(failures.map { $0["title"] as? String } == ["CrashTests/testOutOfRange"])
        #expect(failures.map { $0["message"] as? String } == ["Crash: xctest at CrashTests.testOutOfRange()"])
        #expect(failures.map { $0["isTest"] as? Bool } == [true])
        #expect(report["isVerdictOnly"] == nil)
    }

    /// Without a bundle to read, the log's verdict is all there is: the outcome, said to be no more than that.
    @Test func aLogWithoutABundleToReadIsItsVerdictOnly() async throws {
        let run = await Run("report", "--server", "MobileBuildMCP", "--kind", "test", "--log", try Self.log("TEST EXECUTE SUCCEEDED"))
        let report = try Self.json(run)
        #expect(report["ok"] as? Bool == true)
        #expect(report["isVerdictOnly"] as? Bool == true)
    }

    static let twoConfigurations = #"{"testNodes":[{"nodeType":"Test Plan Configuration","name":"English","children":[{"nodeType":"Test Case","nodeIdentifier":"CrashTests/testOutOfRange()","name":"testOutOfRange()","result":"Failed","children":[{"nodeType":"Failure Message","name":"Crash: in English"}]}]},{"nodeType":"Test Plan Configuration","name":"German","children":[{"nodeType":"Test Case","nodeIdentifier":"CrashTests/testOutOfRange()","name":"testOutOfRange()","result":"Failed","children":[{"nodeType":"Failure Message","name":"Crash: in German"}]}]}]}"#

    /// A test that failed under two test-plan configurations is one failing test, as `look` counts it.
    @Test func aTestFailingUnderTwoConfigurationsIsOneFailure() async throws {
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(Self.bundle) --compact": .init(status: 0, stdout: Self.twoConfigurations)])
        let run = await Run("report", "--server", "MobileBuildMCP", "--kind", "test", "--log", try Self.log("TEST EXECUTE FAILED"), context: .fake(runner))
        let failures = try #require(try Self.json(run)["failures"] as? [[String: Any]])
        #expect(failures.map { $0["title"] as? String } == ["CrashTests/testOutOfRange"])
        #expect(failures.map { $0["message"] as? String } == ["Crash: in English"])
    }

    /// A repeated run told from its log keeps each repeated test's verdict, as a result read does: the ledger tells flaky
    /// from real by it.
    @Test func aRepeatedRunFromItsLogKeepsItsVerdicts() async throws {
        let listing = #"{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"ProbeTests/testFlaky()","name":"testFlaky()","result":"Failed","children":[{"nodeType":"Repetition","name":"Repetition 1","result":"Failed"},{"nodeType":"Repetition","name":"Repetition 2","result":"Passed"}]}]}"#
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(Self.bundle) --compact": .init(status: 0, stdout: listing)])
        let run = await Run("report", "--server", "MobileBuildMCP", "--kind", "test", "--repeated", "--log", try Self.log("TEST EXECUTE FAILED"), context: .fake(runner))
        let repeated = try #require(try Self.json(run)["repeated"] as? [[String: Any]])
        #expect(repeated.map { $0["verdict"] as? String } == ["flaky"])
    }

    /// One call reads both: the notification first, then, when it has no result to read, the run's log.
    @Test func aNotificationWithoutAResultIsToldFromTheLog() async throws {
        let read = await Run("report", "--server", "MobileBuildMCP", "--kind", "build", "--notification", "--log", try Self.log("BUILD SUCCEEDED"), stdin: Self.notification(Self.failed))
        #expect(try Self.json(read)["ok"] as? Bool == false)
        let run = await Run("report", "--server", "MobileBuildMCP", "--kind", "test", "--notification", "--log", try Self.log("TEST EXECUTE SUCCEEDED"), stdin: Self.notification("", status: "killed"))
        let report = try Self.json(run)
        #expect(report["ok"] as? Bool == true)
        #expect(report["isUnread"] == nil)
        #expect(report["isVerdictOnly"] as? Bool == true)
    }

    /// A log with no verdict yet, or none at all, says no outcome.
    @Test func aLogWithoutAVerdictIsUnread() async throws {
        let run = await Run("report", "--server", "MobileBuildMCP", "--kind", "build", "--log", "/nonexistent/build_sim.log")
        #expect(try Self.json(run)["isUnread"] as? Bool == true)
    }
}

/// The field fixture's type error, as MobileBuildMCP answered the build, arriving in a task's notification: read and
/// shortened as when the call answered in the foreground, with the notification kept around it.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedBackgroundReportTests {
    @Test func aNotifiedBuildIsShortenedInItsNotification() async throws {
        let failed = try String(contentsOf: Testbed.root.appending(path: "captures/field/type-error.txt"), encoding: .utf8)
        let direct = try BackgroundReportTests.json(await Run("report", "--server", "MobileBuildMCP", "--kind", "build", stdin: failed))
        let notified = try BackgroundReportTests.json(await Run("report", "--server", "MobileBuildMCP", "--kind", "build", "--notification", stdin: BackgroundReportTests.notification(failed)))
        #expect(notified["ok"] as? Bool == false)
        #expect((notified["failures"] as? [[String: Any]])?.count == (direct["failures"] as? [[String: Any]])?.count)
        let shorter = try #require(direct["result"] as? String)
        #expect(notified["result"] as? String == BackgroundReportTests.notification(shorter))
    }
}
