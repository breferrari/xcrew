import Foundation
import Testing
@testable import XcrewCore
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

    /// A notification whose result Claude Code saved for its size: the shorter result comes back, its warnings counted.
    @Test func aSavedResultInANotificationComesBackShorter() async throws {
        let warnings = (1...354).map { #"{"message":"unused \#($0)","location":"/testbed/field/A\#($0).swift:1"}"# }.joined(separator: ",")
        let json = #"{"schema":"mobilebuildmcp.output.test-result","data":{"summary":{"status":"SUCCEEDED","counts":{"passed":1,"failed":0,"skipped":0}},"diagnostics":{"warnings":[\#(warnings)],"errors":[]}}}"#
        let folder = Project.temporary()
        folder.write(json, to: "claude/projects/-work-App/0b6e4c1a/tool-results/mcp-test_sim-1.txt")
        let saved = folder.root.appending(path: "claude/projects/-work-App/0b6e4c1a/tool-results/mcp-test_sim-1.txt").path
        let notice = "Error: result (119,619 characters) exceeds maximum allowed tokens. Output has been saved to \(saved).\nFormat: JSON"
        let report = try Self.json(await Run("report", "--server", "MobileBuildMCP", "--kind", "test", "--notification", stdin: Self.notification(notice)))
        let result = try #require(report["result"] as? String, "\(report)")
        #expect(result.contains("354 warnings left out to keep this result short; the full result is in \(saved)"), "\(result)")
        #expect(result.count < 1_000, "\(result.count) characters")
    }

    /// A task killed, one failed with a text that isn't the server's ("the server went away"), or a text that isn't a
    /// notification, has no result to read: the run's log decides.
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

    /// A report given no time left reads nothing more from the bundle, and says in one line what it left out.
    @Test func aReportPastItsTimeSaysWhatItLeftOut() async throws {
        let listing = #"{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"CrashTests/testOutOfRange()","name":"testOutOfRange()","result":"Failed"}]}"#
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(Self.bundle) --compact": .init(status: 0, stdout: listing)])
        let run = await Run("report", "--server", "MobileBuildMCP", "--kind", "test", "--log", try Self.log("TEST EXECUTE FAILED"), context: .fake(runner, environment: ["XCREW_WITHIN_MS": "1"]))
        let report = try Self.json(run)
        #expect(report["failures"] as? [[String: Any]] == nil || (report["failures"] as? [[String: Any]])?.isEmpty == true)
        #expect((report["notes"] as? [String])?.last == "xcrew: this call's time ran out before xcresulttool answered, so what it reads is left out of this result.", "\(report)")
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

    /// Run logs in `context`'s MobileBuildMCP workspace folder, each named and naming the scheme its run built, ending on
    /// `verdict`.
    @discardableResult
    static func logs(_ named: [(String, String)], in context: CheckContext, verdict: String = "** TEST EXECUTE SUCCEEDED **") throws -> URL {
        let logs = context.machine.home.appending(path: "Library/Developer/MobileBuildMCP/workspaces/\(RunLog.workspaceKey(root: context.project.root.path))/logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        for (name, scheme) in named {
            try "Command line invocation:\n    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -scheme \(scheme) -destination id=0000\n\n\(verdict)\n".write(to: logs.appending(path: name), atomically: true, encoding: .utf8)
        }
        return logs
    }

    /// A notification's report found with the tool and the call's start, over the logs `named`.
    static func notified(since: String, logs named: [(String, String)], tool: String = "test_sim") async throws -> Run {
        let context = CheckContext.fake()
        try logs(named, in: context)
        return await Run("report", "--server", "MobileBuildMCP", "--kind", "test", "--notification", "--tool", tool, "--since", since, context: context, stdin: Self.notification("", status: "killed"))
    }

    /// A notification read with the tool and the call's start, and no log, finds the run's own log in its workspace: the
    /// log may appear only after Claude Code moved the call, when nothing followed it any more.
    @Test func aNotificationWithoutALogFindsTheRunsLog() async throws {
        let report = try Self.json(try await Self.notified(since: "0", logs: [("test_sim_2026-11-02T10-00-00-000Z_pid1_abcd1234.log", "Feature")]))
        #expect(report["scheme"] as? String == "Feature")
        #expect(report["ok"] as? Bool == true)
        #expect(report["isUnread"] == nil)
    }

    /// The run's log is the first MobileBuildMCP named at or after the call's start, by the time in its name: a later
    /// call's log is another run's, and one named before the start is an earlier run's. The call started at 10:00:00 UTC
    /// on November 2, 2026, 1,793,613,600,000 ms after the epoch. Each log was last written a minute or more after it was
    /// named, at 10:01:00, 10:01:40 and 10:05:00 (1,793,613,660 s on), so the later run's is the newest written: picking
    /// by writing, as the band does while a run goes, would take it.
    @Test func aNotificationsLogIsTheFirstNamedSinceTheCallStarted() async throws {
        let context = CheckContext.fake()
        let logs = try Self.logs([("test_sim_2026-11-02T09-59-00-000Z_pid1_abcd1234.log", "Earlier"), ("test_sim_2026-11-02T10-00-05-000Z_pid1_abcd1234.log", "Feature"), ("test_sim_2026-11-02T10-04-00-000Z_pid1_abcd1234.log", "Later")], in: context)
        for (name, written) in [("2026-11-02T09-59-00-000Z", 1_793_613_660.0), ("2026-11-02T10-00-05-000Z", 1_793_613_700), ("2026-11-02T10-04-00-000Z", 1_793_613_900)] {
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: written)], ofItemAtPath: logs.appending(path: "test_sim_\(name)_pid1_abcd1234.log").path)
        }
        let run = await Run("report", "--server", "MobileBuildMCP", "--kind", "test", "--notification", "--tool", "test_sim", "--since", "1793613600000", context: context, stdin: Self.notification("", status: "killed"))
        let scheme = try Self.json(run)["scheme"] as? String
        #expect(scheme == "Feature")
    }

    /// A result read as it came, with the tool and the call's start, names the scheme of the run's log, as a run too fast
    /// for the band to have read its log needs; the outcome is still the result's.
    @Test func aResultWithTheToolAndStartNamesItsLogsScheme() async throws {
        let context = CheckContext.fake()
        try Self.logs([("build_sim_2026-11-02T10-00-01-000Z_pid1_abcd1234.log", "Feature")], in: context, verdict: "** BUILD FAILED **")
        let run = await Run("report", "--server", "MobileBuildMCP", "--kind", "build", "--tool", "build_sim", "--since", "1793613600000", context: context, stdin: "✅ Build succeeded for scheme Feature.")
        let report = try Self.json(run)
        #expect(report["scheme"] as? String == "Feature")
        #expect(report["ok"] as? Bool == true)
    }

    /// A log opened in the same millisecond as the call began is the run's: 10:00:00.259 UTC on November 2, 2026 is
    /// 1,793,613,600,259 ms after the epoch.
    @Test func aLogOpenedInTheCallsOwnMillisecondIsItsRuns() async throws {
        let run = try await Self.notified(since: "1793613600259", logs: [("test_sim_2026-11-02T10-00-00-259Z_pid1_abcd1234.log", "Feature")])
        let scheme = try Self.json(run)["scheme"] as? String
        #expect(scheme == "Feature")
    }

    /// The call's start is a number of milliseconds, as the mod's clock gives it: anything else is the mod's mistake.
    @Test(arguments: ["soon", "nan", "inf", "-inf"])
    func aStartThatIsntWholeMillisecondsIsAUsageError(since: String) async throws {
        let run = try await Self.notified(since: since, logs: [])
        #expect(run.status != 0)
        #expect(run.errors == ["report --tool needs --since, in milliseconds"])
    }

    /// A start with a fraction of a millisecond, which the engine's clock doesn't rule out, counts from its whole
    /// millisecond, as a log's name gives it.
    @Test func aStartWithAFractionCountsFromItsWholeMillisecond() async throws {
        let run = try await Self.notified(since: "1793613600259.5", logs: [("test_sim_2026-11-02T10-00-00-259Z_pid1_abcd1234.log", "Feature")])
        let scheme = try Self.json(run)["scheme"] as? String
        #expect(scheme == "Feature")
    }

    /// Another tool whose name starts with this one's, as `test_sim_foo` would, logs another run.
    @Test func aLongerToolsLogIsntTheRuns() async throws {
        let run = try await Self.notified(since: "1793613600000", logs: [("test_sim_foo_2026-11-02T10-00-01-000Z_pid1_abcd1234.log", "Other"), ("test_sim_2026-11-02T10-00-02-000Z_pid1_abcd1234.log", "Feature")])
        let scheme = try Self.json(run)["scheme"] as? String
        #expect(scheme == "Feature")
    }

    /// A notification read from a build and run's log, when its own text can't be read: the build's success is no
    /// outcome, since the app was installed and launched after it; a failed build is.
    @Test(arguments: [("** BUILD SUCCEEDED **", true), ("** BUILD FAILED **", false)])
    func aBuildAndRunsLogGivesOnlyAFailedBuildAsItsOutcome(verdict: String, unread: Bool) async throws {
        let project = Project.temporary()
        project.write("CompileSwift normal arm64 /w/A.swift (in target 'App' from project 'App')\n\(verdict)\n", to: "build_run_sim_1.log")
        let log = project.root.appending(path: "build_run_sim_1.log").path
        let report = try Self.json(await Run("report", "--server", "MobileBuildMCP", "--kind", "build", "--notification", "--launches", "--log", log, stdin: Self.notification("", status: "killed")))
        #expect((report["isUnread"] as? Bool == true) == unread, "\(report)")
        if !unread { #expect(report["ok"] as? Bool == false) }
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
