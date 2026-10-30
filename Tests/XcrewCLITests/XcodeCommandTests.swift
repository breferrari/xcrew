import Foundation
import Testing
@testable import XcrewCLI
@testable import XcrewCore
import XcrewTestSupport

/// `xcrew xcode`: the Xcodes a project's tools can build with, and the developer folder its pin names, which the
/// MobileBuildMCP launcher sets as `DEVELOPER_DIR`.
@Suite struct XcodeCommandTests {
    /// A project on a Mac with Xcode 26.4 and Xcode 27.2 beta 3, 27.2 selected.
    func context(pin: String? = nil) -> (CheckContext, URL) {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        let apps = project.root.appending(path: "Applications")
        FakeXcode.install(in: apps, "Xcode-27.2.0-Beta.3.app", version: "27.2", build: "27B5038j")
        FakeXcode.install(in: apps, "Xcode-26.4.app", version: "26.4", build: "17E192")
        if let pin { project.write(pin, to: ".xcode-version") }
        let runner = FakeRunner(responses: ["xcode-select -p": .init(status: 0, stdout: "\(apps.path)/Xcode-27.2.0-Beta.3.app/Contents/Developer\n")])
        return (CheckContext.fake(runner, project: project, applications: apps), URL(fileURLWithPath: ProjectLayout.canonical(apps)))
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

    @Test func withoutAnOptionItSaysWhichXcodeIsWhich() async {
        let (context, apps) = context(pin: "26.4\n")
        let run = await Run("xcode", context: context)
        #expect(run.status == 0)
        #expect(run.output == [
            "installed: Xcode 27.2 (27B5038j) at \(apps.path)/Xcode-27.2.0-Beta.3.app",
            "installed: Xcode 26.4 (17E192) at \(apps.path)/Xcode-26.4.app",
            "selected: Xcode 27.2",
            "pinned: Xcode 26.4 (.xcode-version), installed at \(apps.path)/Xcode-26.4.app",
            "builds: Xcode 27.2, since MobileBuildMCP started without the pin",
            "CI: names no Xcode version",
            "open: none",
        ])
    }
}
