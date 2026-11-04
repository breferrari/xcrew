import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// A failed test run moved to the background, as Claude Code delivered it in the field (November 4, 2026, xcrew
/// 0.16.0; docs/findings.md, *A call moved to the background*): the summary names the task, and the `<result>` block holds
/// MobileBuildMCP's text after "Task failed: ", all on one line, cut at about 10 KB. Field shape, names neutralised: a
/// module's test target asked for under a scheme that doesn't test it, two errors and 289 warnings; its log ends with
/// xcodebuild's own error and no verdict.
struct OneLineNotificationTests {
    static let failure = ToolOutput.Failure(title: "Failed to build workspace App with scheme App.", message: OutsideSchemeTests.refusal)

    /// The text on one line, as Claude Code gives it: MobileBuildMCP's lines with each run of line breaks and indents a
    /// space, cut at 10,000 characters.
    static let body: String = {
        let warnings = (1...289).map { "⚠ 'old\($0)()' is deprecated: use new() instead [#DeprecatedDeclaration] /work/app/Modules/Kit/Sources/File\($0).swift:99" }
        let text = "🧪 Test Errors (2): ✗ 3 | func log(_ error: any Error, category: String?) ✗ Failed to build workspace App with scheme App.: \(OutsideSchemeTests.refusal) Warnings (289): " + warnings.joined(separator: " ")
        return String(text.prefix(10_000)) + "… [truncated]"
    }()

    static let notification = "<task-notification>\n<task-id>k5dse2p6c</task-id>\n<status>failed</status>\n<summary>MCP task k5dse2p6c (plugin:xcrew:MobileBuildMCP/test_sim) failed.</summary>\n<result>\nTask failed: \(body)\n</result>\n</task-notification>"

    /// Read as the same run in the foreground: its failure, its warnings outside the lines the branch changed counted, and
    /// the note on a target outside the run's scheme, in a result put back in the notification, far shorter.
    @Test func aOneLineFailedNotificationIsReadAsItsResult() async throws {
        let (project, home) = try OutsideSchemeTests.setting(log: false)
        let runner = FakeRunner(responses: FakeRunner.branch(at: project.root, changed: ["Sources/Other.swift"], diffed: [], diff: ""))
        let report = await Report.make(kind: .test, notification: Self.notification, log: nil, server: .mobileBuildMCP, home: home, runner: runner, project: project)
        #expect(report.isUnread == nil)
        #expect(!report.ok)
        #expect(report.failures.contains(Self.failure), "\(report.failures)")
        #expect(report.notes.contains(#"xcrew: this run's scheme doesn't test CoreTests, the target `-only-testing:` names, so Xcode ran none. The Core scheme tests it: `session_set_defaults {"scheme":"Core"}` makes Core the active profile's scheme."#), "\(report.notes)")
        let result = try #require(report.result)
        #expect(result.hasPrefix("<task-notification>\n<task-id>k5dse2p6c</task-id>\n<status>failed</status>"))
        #expect(result.count(where: { $0 == "⚠" }) <= 10, "\(result)")
        #expect(result.count < Self.notification.count / 4, "\(result.count) of \(Self.notification.count) characters")
    }

    /// An error's place is the path at its end, spaces and all, and nothing else: a message ending in a version or a
    /// file's name keeps it.
    @Test func aPlaceIsTheWholePathAtTheEnd() {
        #expect(OneLineText.unfolded("🧪 Test Errors (2): ✗ cannot open the file /work/My App/File.swift:12 ✗ needs version 1.2:3") == "\n🧪 Test\n\nErrors (2):\n\n  ✗ cannot open the file\n    /work/My App/File.swift:12\n\n  ✗ needs version 1.2:3\n")
    }

    /// xcodebuild's error with lines under it, as one naming a destination no simulator matches, ends the log too.
    @Test func aLogEndingInXcodebuildsErrorAndItsDetailIsAFailedRun() async {
        let log = "Command line invocation:\n    xcodebuild build -scheme App\n\nxcodebuild: error: Unable to find a device matching the provided destination specifier:\n\t\t{ platform:iOS Simulator, OS:latest, name:iPhone 1 }\n\n\tThe requested device could not be found because no available devices matched the request.\n\n"
        let report = await Report.make(kind: .build, log: log, runner: FakeRunner())
        #expect(!report.ok && report.isUnread == nil)
        #expect(report.failures == [ToolOutput.Failure(title: "Unable to find a device matching the provided destination specifier:", message: "")])
    }

    /// A run whose log ends with xcodebuild's own error, and no verdict, failed with that error.
    @Test func aLogEndingInXcodebuildsErrorIsAFailedRun() async {
        let log = "Command line invocation:\n    xcodebuild test -workspace App.xcworkspace -scheme App -only-testing:CoreTests\n\nTest session results, code coverage, and logs:\n\t/testbed/user/Library/Developer/MobileBuildMCP/workspaces/app-0000/result-bundles/test_sim.xcresult\n\nxcodebuild: error: Failed to build workspace App with scheme App.: \(OutsideSchemeTests.refusal)\n"
        let report = await Report.make(kind: .test, log: log, runner: FakeRunner())
        #expect(report.isUnread == nil)
        #expect(!report.ok)
        #expect(report.failures == [Self.failure])
    }
}

/// MobileBuildMCP's text, folded onto one line as Claude Code folds a failed task's, unfolds to the text itself: each
/// test bed capture of a build or test run.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct OneLineTextTests {
    static var texts: [(name: String, text: String)] {
        let raw = Testbed.root.appending(path: "captures/raw"), field = Testbed.root.appending(path: "captures/field")
        let rawTexts = ((try? FileManager.default.contentsOfDirectory(atPath: raw.path)) ?? []).sorted().filter { $0.hasSuffix(".json") && !$0.dropLast(5).contains(".") }.compactMap { name -> (String, String)? in
            guard let json = (try? JSONSerialization.jsonObject(with: Data(contentsOf: raw.appending(path: name)))) as? [String: Any] else { return nil }
            return (name, (json["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined())
        }
        let fieldTexts = ((try? FileManager.default.contentsOfDirectory(atPath: field.path)) ?? []).sorted().filter { $0.hasSuffix(".txt") }.compactMap { name in
            (try? String(contentsOf: field.appending(path: name), encoding: .utf8)).map { (name, $0) }
        }
        return (rawTexts + fieldTexts).filter { $0.1.hasPrefix("\n🧪 ") || $0.1.hasPrefix("\n🔨 ") }
    }

    /// The captures one line can't give back whole, and what it loses: the spacing inside a compiler excerpt, a Swift
    /// Testing failure's detail lines, which join its message, and xcodebuild's raw output, which stays on one line.
    static let lossy: [String: String] = [
        "test-build-failed.json": "excerpt", "type-error.txt": "excerpt",
        "nested.json": "details", "nested-retry.json": "details", "shapes.json": "details",
        "shapes-configurations.json": "raw output", "shapes-iterations.json": "raw output",
    ]

    /// Every other capture comes back byte for byte; one that loses something still reads as the same run: its
    /// outcome, summary, failures and warnings.
    @Test func eachCaptureUnfoldsToItself() throws {
        #expect(Self.texts.count > 10, "\(Self.texts.map(\.name))")
        for (name, text) in Self.texts {
            let folded = text.trimmingCharacters(in: .whitespacesAndNewlines).replacing(#/\s+/#, with: " ")
            let unfolded = try #require(OneLineText.unfolded(folded), "\(name)")
            guard Self.lossy[name] != nil else {
                #expect(unfolded == text, "\(name)")
                continue
            }
            let (read, original) = (ToolOutput(text: unfolded, server: .mobileBuildMCP), ToolOutput(text: text, server: .mobileBuildMCP))
            #expect(read.summary.ok == original.summary.ok && read.summary.detail == original.summary.detail, "\(name)")
            #expect(read.failures.map(\.title) == original.failures.map(\.title), "\(name)")
            #expect(read.warnings.count == original.warnings.count, "\(name)")
        }
    }

    /// Every capture named as losing something is one that does.
    @Test func eachLossyCaptureLosesSomething() {
        let texts = Dictionary(uniqueKeysWithValues: Self.texts.map { ($0.name, $0.text) })
        for name in Self.lossy.keys {
            let text = texts[name] ?? ""
            #expect(OneLineText.unfolded(text.trimmingCharacters(in: .whitespacesAndNewlines).replacing(#/\s+/#, with: " ")) != text, "\(name)")
        }
    }
}

/// A one-line notification of a run with a result bundle: the failures are the bundle's, whole, as in the foreground,
/// though one line joins a Swift Testing failure's detail lines to its message. The test bed's `shapes` run, folded as
/// Claude Code folds a failed task's text: whole, and cut before its summary and the files that name the bundle, whose
/// log names it.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct OneLineBundleTests {
    static func runner() throws -> FakeRunner {
        let bundle = try Raw.bundle("shapes")
        var responses = ["xcrun xcresulttool get test-results tests --path \(bundle) --compact": CommandResult(status: 0, stdout: try Raw.file("shapes.tests.json"))]
        for test in ["fails", "knownIssue"] {
            responses["xcrun xcresulttool get test-results test-details --test-id ShapesTests/\(test)() --path \(bundle) --compact"] = .init(status: 0, stdout: try Raw.file("shapes.details.ShapesTests.\(test).json"))
        }
        return FakeRunner(responses: responses)
    }

    static func notification(_ text: String) -> String {
        "<task-notification>\n<task-id>k5dse2p6c</task-id>\n<status>failed</status>\n<summary>MCP task k5dse2p6c (plugin:xcrew:MobileBuildMCP/test_sim) failed.</summary>\n<result>\nTask failed: \(text)\n</result>\n</task-notification>"
    }

    /// `fails()`'s failure as the bundle records it, as the foreground report gives it.
    static let fails = ToolOutput.Failure(title: "ShapesTests/fails", message: #"Expectation failed: Kit.name == "Other""#, where: "ShapesTests.swift:10", isTest: true, target: "KitTests")

    static let folded: String = (try? Raw.text("shapes"))?.trimmingCharacters(in: .whitespacesAndNewlines).replacing(#/\s+/#, with: " ") ?? ""

    @Test func aOneLineNotificationsFailuresAreTheBundles() async throws {
        let report = await Report.make(kind: .test, notification: Self.notification(Self.folded), log: nil, server: .mobileBuildMCP, home: Captured.home, runner: try Self.runner())
        #expect(report.failures == [Self.fails], "\(report.failures)")
    }

    @Test func aCutNotificationsFailuresAreTheBundleItsLogNames() async throws {
        let cut = String(Self.folded[..<(Self.folded.range(of: " ❌ ")?.lowerBound ?? Self.folded.endIndex)]) + "… [truncated]"
        let log = FileManager.default.temporaryDirectory.appending(path: "xcrew-shapes-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        try "Test session results, code coverage, and logs:\n\t\(try Raw.bundle("shapes"))\n\n** TEST EXECUTE FAILED **\n".write(to: log, atomically: true, encoding: .utf8)
        let report = await Report.make(kind: .test, notification: Self.notification(cut), log: log.path, server: .mobileBuildMCP, home: Captured.home, runner: try Self.runner())
        #expect(report.failures == [Self.fails], "\(report.failures)")
        #expect(report.bundle == (try Raw.bundle("shapes")))
    }
}
