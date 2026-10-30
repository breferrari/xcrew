import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// The doctor on which Xcode a session builds with: the project's pin, CI's, and the Xcode the Xcode MCP works through.
@Suite struct XcodeChecksTests {
    /// A project on a Mac with Xcode 26.4 and Xcode 27.2 beta 3, 27.2 selected, and what the MobileBuildMCP launcher
    /// last recorded, `launch`, when given.
    func context(pin: String? = nil, workflow: String? = nil, running: String? = nil, launch: String? = nil, onlyOne: Bool = false) -> CheckContext {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        let apps = project.root.appending(path: "Applications")
        if onlyOne { FakeXcode.install(in: apps, "Xcode-27.2.0-Beta.3.app", version: "27.2", build: "27B5038j") } else { FakeXcode.installBoth(in: apps) }
        if let pin { project.write(pin, to: ".xcode-version") }
        if let workflow { project.write(workflow, to: ".github/workflows/ci.yml") }
        let processes = running.map { "  202 \(apps.path)/\($0)/Contents/MacOS/Xcode\n" } ?? ""
        let context = CheckContext.fake(FakeRunner(responses: [
            "xcode-select -p": .init(status: 0, stdout: "\(apps.path)/Xcode-27.2.0-Beta.3.app/Contents/Developer\n"),
            "ps -axo pid=,comm=": .init(status: 0, stdout: "  101 /usr/sbin/cfprefsd\n\(processes)"),
        ]), project: project, applications: apps)
        if let launch {
            let record = Xcodes.launchRecord(of: project, on: context.machine)
            try! FileManager.default.createDirectory(at: record.deletingLastPathComponent(), withIntermediateDirectories: true)
            try! launch.replacingOccurrences(of: "APPS", with: apps.path).write(to: record, atomically: true, encoding: .utf8)
        }
        return context
    }

    static let ciOn26_3 = "jobs:\n  test:\n    steps:\n      - uses: maxim-lobanov/setup-xcode@v1\n        with:\n          xcode-version: '26.3'\n"

    @Test func aPinNoInstalledXcodeMatchesFailsWithTheInstall() async {
        let result = await XcodePinCheck().run(context(pin: "25.0\n"))
        #expect(result.status == .fail)
        #expect(result.message == "the project pins Xcode 25.0 (.xcode-version), but no installed Xcode is 25.0, so MobileBuildMCP builds with Xcode 27.2: xcodes install 25.0")
    }

    @Test func aPinTheServerStartedWithPasses() async {
        let result = await XcodePinCheck().run(context(pin: "26.4\n", launch: "applied APPS/Xcode-26.4.app/Contents/Developer\n"))
        #expect(result.status == .pass)
        #expect(result.message.contains("26.4"))
    }

    /// The launcher says why it didn't apply the pin: the CLI wasn't built yet, or answered too late.
    @Test func aPinTheServerStartedWithoutWarnsWhy() async {
        let result = await XcodePinCheck().run(context(pin: "26.4\n", launch: "timed out 2\n"))
        #expect(result.status == .warn)
        #expect(result.message == "the project pins Xcode 26.4 (.xcode-version), but MobileBuildMCP started without it (the xcrew CLI took longer than 2 s), so it builds with Xcode 27.2: restart Claude Code")
    }

    /// A server started before the pin, or before xcrew applied pins, left no record of it.
    @Test func aPinWithNoRecordOfTheServerStartWarns() async {
        let result = await XcodePinCheck().run(context(pin: "26.4\n"))
        #expect(result.status == .warn)
        #expect(result.message.contains("MobileBuildMCP started without it"))
    }

    @Test func withoutAPinSeveralXcodesAndCIsVersionSuggestOne() async {
        let result = await XcodePinCheck().run(context(workflow: Self.ciOn26_3))
        #expect(result.status == .warn)
        #expect(result.message == "several Xcodes are installed and CI uses Xcode 26.3 (.github/workflows/ci.yml:6), but nothing pins one, so builds use Xcode 27.2: pin CI's with echo 26.3 > .xcode-version")
    }

    @Test func withoutAPinOneXcodeHasNothingToChoose() async {
        let result = await XcodePinCheck().run(context(workflow: Self.ciOn26_3, onlyOne: true))
        #expect(result.status == .pass)
    }

    @Test func ciOnAnotherXcodeWarnsWithWhere() async {
        let result = await XcodeCICheck().run(context(pin: "26.4\n", workflow: Self.ciOn26_3, launch: "applied APPS/Xcode-26.4.app/Contents/Developer\n"))
        #expect(result.status == .warn)
        #expect(result.message == "CI uses Xcode 26.3 (.github/workflows/ci.yml:6), but this project pins Xcode 26.4, so results can differ from CI's: move CI to 26.4, or pin 26.3 in .xcode-version")
    }

    @Test func ciOnTheSameXcodePasses() async {
        let result = await XcodeCICheck().run(context(pin: "26.3\n", workflow: Self.ciOn26_3))
        #expect(result.status == .pass)
    }

    /// The Xcode MCP works through the Xcode that's open; a pin can't change it.
    @Test func theOpenXcodeOtherThanTheBuildsOneIsTwoToolchains() async {
        let result = await XcodeOpenCheck().run(context(pin: "26.4\n", running: "Xcode-27.2.0-Beta.3.app", launch: "applied APPS/Xcode-26.4.app/Contents/Developer\n"))
        #expect(result.status == .warn)
        #expect(result.message.hasPrefix("two toolchains in one session: the Xcode MCP works through the open Xcode 27.2, but MobileBuildMCP builds with Xcode 26.4, so their builds, errors and tests can disagree: quit Xcode 27.2 and open "))
        #expect(result.message.hasSuffix("/Xcode-26.4.app"))
    }

    @Test func theOpenXcodeTheSameAsTheBuildsOnePasses() async {
        let result = await XcodeOpenCheck().run(context(running: "Xcode-27.2.0-Beta.3.app"))
        #expect(result.status == .pass)
    }

    @Test func noOpenXcodeHasNothingToCompare() async {
        let result = await XcodeOpenCheck().run(context(pin: "26.4\n", launch: "applied APPS/Xcode-26.4.app/Contents/Developer\n"))
        #expect(result.status == .pass)
        #expect(result.message == "Xcode isn't open")
    }
}
