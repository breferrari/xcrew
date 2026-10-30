import Foundation
import Testing
@testable import XcrewCLI
@testable import XcrewCore
import XcrewTestSupport

/// `xcrew xcode`: the Xcodes a project's tools can build with, and the developer folder its pin names, which the
/// MobileBuildMCP launcher sets as `DEVELOPER_DIR`.
@Suite struct XcodeCommandTests {
    /// A project on a Mac with Xcode 26.4 and Xcode 27.2 beta 3, 27.2 selected.
    func context(pin: String? = nil, serving: Bool = false) -> (CheckContext, URL) {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        let apps = project.root.appending(path: "Applications")
        FakeXcode.installBoth(in: apps)
        if let pin { project.write(pin, to: ".xcode-version") }
        var responses = FakeSession.responses(serving: serving ? project : nil)
        responses["xcode-select -p"] = .init(status: 0, stdout: "\(apps.path)/Xcode-27.2.0-Beta.3.app/Contents/Developer\n")
        return (CheckContext.fake(FakeRunner(responses: responses), project: project, processID: FakeSession.doctor, applications: apps), URL(fileURLWithPath: ProjectLayout.canonical(apps)))
    }

    @Test func thePinsDeveloperFolderIsPrinted() async {
        let (context, apps) = context(pin: "26.4\n")
        let run = await Run("xcode", "--developer-dir", context: context)
        #expect(run.status == 0)
        #expect(run.output == ["\(apps.path)/Xcode-26.4.app/Contents/Developer"])
    }

    /// The launcher tells these apart in what it records: no pin, and a pin nothing installed matches.
    @Test func withoutAPinOrAMatchNothingIsPrinted() async {
        let unpinned = await Run("xcode", "--developer-dir", context: context().0)
        #expect(unpinned.status == XcodeCommand.noPin)
        #expect(unpinned.output == [])
        let unmatched = await Run("xcode", "--developer-dir", context: context(pin: "25.0").0)
        #expect(unmatched.status == XcodeCommand.noMatch)
        #expect(unmatched.output == [])
    }

    /// A server started with another Xcode than the pin's, the pin changed since, didn't start with the pin: the command
    /// says so as `xcode/pin` does.
    @Test func aServerStartedWithAnotherXcodeIsNotThePins() async throws {
        let (context, apps) = context(pin: "26.4\n", serving: true)
        let record = Xcodes.launchRecord(of: context.project, on: context.machine)
        try FileManager.default.createDirectory(at: record.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "applied \(apps.path)/Xcode-27.2.0-Beta.3.app/Contents/Developer\n".write(to: record, atomically: true, encoding: .utf8)
        let run = await Run("xcode", context: context)
        #expect(run.output.contains("builds: Xcode 27.2, since MobileBuildMCP started without the pin"), "\(run.output)")
    }

    /// The CI line names the version a workflow reads from the pin file, at the line that reads it.
    @Test func aWorkflowReadingThePinIsCIsXcode() async {
        let (context, _) = context(pin: "26.4\n")
        context.project.write("jobs:\n  test:\n    steps:\n      - run: sudo xcode-select -s \"/Applications/Xcode_$(cat .xcode-version).app\"\n", to: ".github/workflows/ci.yml")
        let run = await Run("xcode", context: context)
        #expect(run.output.contains("CI: Xcode 26.4 (.github/workflows/ci.yml:4)"), "\(run.output)")
    }

    @Test func withoutAnOptionItSaysWhichXcodeIsWhich() async {
        let (context, apps) = context(pin: "26.4\n")
        let run = await Run("xcode", context: context)
        #expect(run.status == 0)
        #expect(run.output == [
            "installed: Xcode 27.2 (27B5038j) at \(apps.path)/Xcode-27.2.0-Beta.3.app",
            "installed: Xcode 26.4 (17E192) at \(apps.path)/Xcode-26.4.app",
            "selected: Xcode 27.2",
            "pinned: Xcode 26.4 (.xcode-version), installed at \(apps.path)/Xcode-26.4.app",
            "builds: Xcode 26.4, when MobileBuildMCP starts",
            "CI: names no Xcode version",
            "open: none",
        ])
    }
}
