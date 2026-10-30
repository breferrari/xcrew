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

    /// A fresh folder for one test's files, removed after `body`.
    static func inFolder<T>(_ body: (URL) async throws -> T) async throws -> T {
        let root = FileManager.default.temporaryDirectory.appending(path: "xcrew-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        return try await body(root)
    }

    /// A bundle that answers as the capture's run did: its test list and each failed test's activities, with every
    /// export a fresh copy of the capture's under `root`.
    static func bundle(_ capture: String, root: URL) throws -> ResultBundle {
        let path = "/runs/UITests.xcresult"
        var responses = ["xcrun xcresulttool get test-results tests --path \(path) --compact": CommandResult(status: 0, stdout: try Self.capture(capture, "tests.json"))]
        for name in ["testFailsAfterTaps", "testMissingElement", "testPlanA", "testRenamedLabel"] {
            responses["xcrun xcresulttool get test-results activities --test-id UITests/\(name)() --path \(path) --compact"] = CommandResult(status: 0, stdout: try Self.capture(capture, "activities-\(name).json"))
        }
        let export: @Sendable () -> URL = {
            let folder = root.appending(path: "export-\(UUID().uuidString)")
            try? FileManager.default.copyItem(at: captures.appending(path: capture), to: folder)
            return folder
        }
        return ResultBundle(path: path, runner: FakeRunner(responses: responses), exportFolder: export)
    }

    /// What `look` says about the `xcodebuild` capture's run, for one test or, with none, for its failed UI tests, and
    /// the folder it kept screens in, gone by the time this returns.
    static func report(_ test: TestID?) async throws -> (text: String, images: URL) {
        try await inFolder { root in
            (await Look.report(bundle: try bundle("xcodebuild", root: root), test: test, keptIn: root.appending(path: "images")), root.appending(path: "images"))
        }
    }

    /// The screen at the run `pick` chooses among a test's failed runs, from a copy of the capture's export.
    static func screen(_ capture: String, _ name: String, data: Bool = false, run pick: ([FailedRun]) -> FailedRun?) async throws -> (screen: FailureScreen?, images: URL, png: Data?) {
        try await inFolder { root in
            let export = root.appending(path: "export")
            try FileManager.default.copyItem(at: captures.appending(path: capture), to: export)
            let test = TestID(suite: "UITests", name: name)
            let run = try #require(pick(FailedRun.runs(activities: try Self.capture(capture, "activities-\(name).json")) ?? []))
            let screen = await FailureScreen.keep(of: test, run: run, attachments: FailureImages.attachments(of: test, in: export), from: export, in: root.appending(path: "images"))
            // Read before the folder goes.
            return (screen, root.appending(path: "images"), screen.flatMap { FileManager.default.contents(atPath: $0.path) })
        }
    }

    @Test func eachFailedRunNamesItsConfigurationDeviceAndTheStepsBeforeItsFailure() throws {
        let runs = FailedRun.runs(activities: try Self.capture("xcodebuild", "activities-testFailsAfterTaps.json")) ?? []
        #expect(runs.map(\.configuration) == ["Plan A", "Plan B"])
        #expect(runs.map(\.device) == ["iPhone 18 Pro Max, iOS 27.2", "iPhone 18 Pro Max, iOS 27.2"])
        let first = try #require(runs.first)
        #expect(first.steps == [#"Open dev.xcrew.testbed.App"#, #"Tap "continue" Button"#, #"Tap "continue" Button"#, #"Find the "title" StaticText"#])
        #expect(first.failure == #"XCTAssertEqual failed: ("Done") is not equal to ("Welcome")"#)
        #expect(first.failedAt == 1793372009.75)
    }

    /// A run that passed has no failure to look at: `testPlanA` fails under Plan B only.
    @Test func aRunThatPassedIsLeftOut() throws {
        let runs = FailedRun.runs(activities: try Self.capture("xcodebuild", "activities-testPlanA.json")) ?? []
        #expect(runs.map(\.configuration) == ["Plan B"])
    }

    /// `look` exports only the recordings, by a glob over their file names: every recording in both captures is named
    /// `….mp4`, as exported and as suggested, so the glob matches it whichever name it reads, and nothing else is.
    @Test(arguments: ["xcodebuild", "mobilebuildmcp"])
    func theRecordingsFilterNamesEveryRecordingAndNothingElse(capture: String) throws {
        let folder = Self.captures.appending(path: capture)
        let manifest = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appending(path: "manifest.json"))) as? [[String: Any]])
        let attachments = manifest.flatMap { $0["attachments"] as? [[String: Any]] ?? [] }
        #expect(FailureScreen.recordings == "*.mp4")
        #expect(attachments.contains { FailureScreen.isMovie(folder.appending(path: $0["exportedFileName"] as? String ?? "")) })
        for attachment in attachments {
            let isRecording = FailureScreen.isMovie(folder.appending(path: attachment["exportedFileName"] as? String ?? ""))
            for key in ["exportedFileName", "suggestedHumanReadableName"] {
                #expect(((attachment[key] as? String) ?? "").hasSuffix(".mp4") == isRecording, "\(attachment)")
            }
        }
    }

    /// The screen at a failure is the last frame of that run's own recording, which stops at the failure: Plan B's,
    /// not Plan A's, for a test that failed under both.
    @Test(arguments: ["xcodebuild", "mobilebuildmcp"])
    func theScreenAtAFailureIsTheLastFrameOfItsRunsRecording(capture: String) async throws {
        let (found, images, png) = try await Self.screen(capture, "testMissingElement") { $0.last }
        let screen = try #require(found)
        #expect(screen.path.hasPrefix(images.appending(path: "UITests/testMissingElement").path))
        #expect(screen.path.hasSuffix("Plan B.png"))
        let data = try #require(png)
        #expect(data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        // The capture's recordings are re-encoded at 88 by 192 points.
        #expect(data.dropFirst(16).prefix(8) == Data([0, 0, 0, 88, 0, 0, 0, 192]))
        #expect(screen.secondsBefore < 0.5)
    }

    /// A test repeated with `-test-iterations` fails more than once on one device and configuration: each run's screen
    /// is kept under a name of its own, so a later run's doesn't replace an earlier one's.
    @Test func eachRepeatedRunKeepsItsOwnScreen() async throws {
        try await Self.inFolder { root in
            let export = root.appending(path: "export")
            try FileManager.default.copyItem(at: Self.captures.appending(path: "xcodebuild"), to: export)
            let test = TestID(suite: "UITests", name: "testMissingElement")
            let run = try #require(FailedRun.runs(activities: try Self.capture("xcodebuild", "activities-testMissingElement.json"))?.last)
            let attachments = FailureImages.attachments(of: test, in: export)
            let first = try #require(await FailureScreen.keep(of: test, run: run, number: 1, attachments: attachments, from: export, in: root.appending(path: "images")))
            let second = try #require(await FailureScreen.keep(of: test, run: run, number: 2, attachments: attachments, from: export, in: root.appending(path: "images")))
            #expect(first.path != second.path)
            #expect(FileManager.default.fileExists(atPath: first.path) && FileManager.default.fileExists(atPath: second.path))
        }
    }

    /// The last frame, not the keyframe before it: a recording writes a frame only when the screen changes, so its last
    /// one can sit well before its end, and seeking near the end lands on a keyframe seconds earlier unless told not to.
    @Test func theLastFrameIsTheRecordingsLastNotItsLastKeyframe() async throws {
        let frame = try await Self.inFolder { root in
            try #require(await FailureScreen.lastFrame(of: Self.captures.appending(path: "xcodebuild/00000000-0000-0000-0000-000000000033.mp4"), to: root.appending(path: "frame.png")))
        }
        // Measured on the capture: its frames' times, and its last keyframe at 7.0.
        #expect(abs(frame.shown - 7.667) < 0.01)
        #expect(frame.length == 7.74)
    }

    /// A run whose recording wasn't kept has no screen.
    @Test func aRunWithNoRecordingHasNoScreen() async throws {
        let (screen, _, _) = try await Self.screen("xcodebuild", "testMissingElement") { runs in
            runs.first.map { FailedRun(device: $0.device, configuration: "Plan C", steps: [], failure: $0.failure, failedAt: $0.failedAt, deviceID: $0.deviceID) }
        }
        #expect(screen == nil)
    }

    /// What Claude reads for a named test: each failed run under its configuration and device, the steps before the
    /// failure, the failure's first line marked, and the screen at it.
    @Test func lookingAtATestShowsEachFailedRunsStepsFailureAndScreen() async throws {
        let (text, images) = try await Self.report(TestID(suite: "UITests", name: "testFailsAfterTaps"))
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
        #expect(lines[7].hasPrefix("    screen: \(images.appending(path: "UITests/UITests/testFailsAfterTaps").path)/"), "\(text)")
        #expect(lines[8] == "  Plan B · iPhone 18 Pro Max, iOS 27.2", "\(text)")
    }

    /// Without a test named, it looks at the failed tests that kept a recording, in the run's order; a passing test and
    /// a passing run are left out.
    @Test func lookingAtARunShowsEachFailedUITest() async throws {
        let (text, _) = try await Self.report(nil)
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
}
