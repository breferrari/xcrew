import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// The test bed's capture of five failing UI tests under a test plan of two configurations, replayed: what
/// `xcresulttool` answered about a run through `xcodebuild test` and one through MobileBuildMCP's `test_sim`.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedLookTests {
    static let captures = Testbed.root.appending(path: "captures/uitests")

    static func capture(_ run: String, _ file: String) throws -> String {
        try String(contentsOf: captures.appending(path: run).appending(path: file), encoding: .utf8)
    }

    @Test func eachFailedRunNamesItsConfigurationDeviceAndTheStepsBeforeItsFailure() throws {
        let runs = FailedRun.runs(activities: try Self.capture("xcodebuild", "activities-testFailsAfterTaps.json"))
        #expect(runs.map(\.configuration) == ["Plan A", "Plan B"])
        #expect(runs.map(\.device) == ["iPhone 18 Pro Max, iOS 27.2", "iPhone 18 Pro Max, iOS 27.2"])
        let first = try #require(runs.first)
        #expect(first.steps == [#"Open dev.xcrew.testbed.App"#, #"Tap "continue" Button"#, #"Tap "continue" Button"#, #"Find the "title" StaticText"#])
        #expect(first.failure == #"XCTAssertEqual failed: ("Done") is not equal to ("Welcome")"#)
        #expect(first.failedAt == 1793372009.75)
    }

    /// A run that passed has no failure to look at: `testPlanA` fails under Plan B only.
    @Test func aRunThatPassedIsLeftOut() throws {
        let runs = FailedRun.runs(activities: try Self.capture("xcodebuild", "activities-testPlanA.json"))
        #expect(runs.map(\.configuration) == ["Plan B"])
    }

    /// A fresh copy of one run's export, as `ResultBundle.attachments` hands one over, in a folder removed afterwards.
    static func export(_ run: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "xcrew-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: captures.appending(path: run), to: root.appending(path: "export"))
        return root
    }

    /// The screen at the failure is the last frame of that run's own recording, which stops at the failure: Plan B's,
    /// not Plan A's, for a test that failed under both.
    @Test(arguments: ["xcodebuild", "mobilebuildmcp"])
    func theScreenAtAFailureIsTheLastFrameOfItsRunsRecording(capture: String) async throws {
        let root = try Self.export(capture)
        defer { try? FileManager.default.removeItem(at: root) }
        let test = TestID(suite: "UITests", name: "testMissingElement")
        let run = try #require(FailedRun.runs(activities: try Self.capture(capture, "activities-testMissingElement.json")).last)
        let screen = try #require(await FailureScreen.keep(of: test, run: run, from: root.appending(path: "export"), in: root.appending(path: "images")))
        #expect(screen.path.hasPrefix(root.appending(path: "images/UITests/testMissingElement").path))
        #expect(screen.path.hasSuffix("Plan B.png"))
        let data = try Data(contentsOf: URL(fileURLWithPath: screen.path))
        #expect(data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        // The capture's recordings are re-encoded at 88 by 192 points.
        #expect(data.dropFirst(16).prefix(8) == Data([0, 0, 0, 88, 0, 0, 0, 192]))
        #expect(screen.secondsBefore < 0.5)
    }

    /// The last frame, not the keyframe before it: a recording writes a frame only when the screen changes, so its last
    /// one can sit well before its end, and seeking near the end lands on a keyframe seconds earlier unless told not to.
    @Test func theLastFrameIsTheRecordingsLastNotItsLastKeyframe() async throws {
        let root = try Self.export("xcodebuild")
        defer { try? FileManager.default.removeItem(at: root) }
        let frame = try #require(await FailureScreen.lastFrame(of: root.appending(path: "export/00000000-0000-0000-0000-000000000033.mp4"), to: root.appending(path: "frame.png")))
        // Measured on the capture: its frames' times, and its last keyframe at 7.0.
        #expect(abs(frame.shown - 7.667) < 0.01)
        #expect(frame.length == 7.74)
    }

    /// A run whose recording wasn't kept has no screen.
    @Test func aRunWithNoRecordingHasNoScreen() async throws {
        let root = try Self.export("xcodebuild")
        defer { try? FileManager.default.removeItem(at: root) }
        let failed = try #require(FailedRun.runs(activities: try Self.capture("xcodebuild", "activities-testMissingElement.json")).first)
        let elsewhere = FailedRun(device: failed.device, configuration: "Plan C", steps: [], failure: failed.failure, failedAt: failed.failedAt, deviceID: failed.deviceID)
        #expect(await FailureScreen.keep(of: TestID(suite: "UITests", name: "testMissingElement"), run: elsewhere, from: root.appending(path: "export"), in: root.appending(path: "images")) == nil)
    }

    /// A bundle that answers as the capture's run did: its test list and each failed test's activities, with every
    /// export a fresh copy of the capture's.
    static func bundle(_ capture: String, root: URL) throws -> ResultBundle {
        let path = "/runs/UITests.xcresult"
        var responses = ["xcrun xcresulttool get test-results tests --path \(path) --compact": CommandResult(status: 0, stdout: try Self.capture(capture, "tests.json"))]
        for name in ["testFailsAfterTaps", "testMissingElement", "testPlanA", "testRenamedLabel"] {
            responses["xcrun xcresulttool get test-results activities --test-id UITests/\(name)() --path \(path) --compact"] = CommandResult(status: 0, stdout: try Self.capture(capture, "activities-\(name).json"))
        }
        let export: @Sendable () -> URL = {
            let folder = root.appending(path: "export-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: captures.appending(path: capture), to: folder)
            return folder
        }
        return ResultBundle(path: path, runner: FakeRunner(responses: responses), exportFolder: export)
    }

    /// What Claude reads for a named test: each failed run under its configuration and device, the steps before the
    /// failure, the failure's first line marked, and the screen at it.
    @Test func lookingAtATestShowsEachFailedRunsStepsFailureAndScreen() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "xcrew-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let text = await Look.report(bundle: try Self.bundle("xcodebuild", root: root), test: TestID(suite: "UITests", name: "testFailsAfterTaps"), keptIn: root.appending(path: "images"))
        let lines = text.components(separatedBy: "\n")
        #expect(lines.prefix(7) == [
            "xcrew look: UITests/testFailsAfterTaps, in UITests.xcresult",
            "  Plan A · iPhone 18 Pro Max, iOS 27.2",
            "    Open dev.xcrew.testbed.App",
            #"    Tap "continue" Button"#,
            #"    Tap "continue" Button"#,
            #"    Find the "title" StaticText"#,
            #"    ✗ XCTAssertEqual failed: ("Done") is not equal to ("Welcome")"#,
        ], "\(text)")
        try #require(lines.count > 8, "\(text)")
        #expect(lines[7].hasPrefix("    screen: \(root.appending(path: "images/UITests/UITests/testFailsAfterTaps").path)/"), "\(text)")
        #expect(lines[8] == "  Plan B · iPhone 18 Pro Max, iOS 27.2", "\(text)")
    }

    /// Without a test named, it looks at the failed tests that kept a recording, in the run's order; a passing test and
    /// a passing run are left out.
    @Test func lookingAtARunShowsEachFailedUITest() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "xcrew-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let text = await Look.report(bundle: try Self.bundle("xcodebuild", root: root), test: nil, keptIn: root.appending(path: "images"))
        let heads = text.components(separatedBy: "\n").filter { !$0.hasPrefix(" ") }
        #expect(heads == [
            "xcrew look: UITests/testFailsAfterTaps, in UITests.xcresult",
            "xcrew look: UITests/testMissingElement, in UITests.xcresult",
            "xcrew look: UITests/testPlanA, in UITests.xcresult",
            "and 1 more failed test: xcrew look UITests/testRenamedLabel",
        ], "\(text)")
        let planA = try #require(text.components(separatedBy: "xcrew look: ").first { $0.hasPrefix("UITests/testPlanA,") })
        #expect(!planA.contains("Plan A ·"), "\(planA)")
        #expect(planA.contains("Plan B ·"), "\(planA)")
    }

    @Test func aTestThatDidNotFailSaysSo() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "xcrew-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let text = await Look.report(bundle: try Self.bundle("xcodebuild", root: root), test: TestID(suite: "UITests", name: "testPasses"), keptIn: root.appending(path: "images"))
        #expect(text == "xcrew: UITests/testPasses didn't fail in UITests.xcresult")
    }
}
