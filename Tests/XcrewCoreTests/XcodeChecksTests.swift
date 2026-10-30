import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// The doctor on which Xcode a session builds with: the project's pin, CI's, and the Xcode the Xcode MCP works through.
@Suite struct XcodeChecksTests {
    /// A project on a Mac with Xcode 26.4 and Xcode 27.2 beta 3, 27.2 selected; this session's MobileBuildMCP serving it,
    /// started `server` ago (`ps`'s `etime`) unless nil; and what the launcher recorded, `launch`, `recorded` seconds ago.
    func context(pin: String? = nil, workflow: String? = nil, running: String? = nil, launch: String? = nil, recorded: TimeInterval = 5, server: String? = "00:30", onlyOne: Bool = false, xcodesTool: Bool = false) -> CheckContext {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        let apps = project.root.appending(path: "Applications")
        if onlyOne { FakeXcode.install(in: apps, "Xcode-27.2.0-Beta.3.app", version: "27.2", build: "27B5038j") } else { FakeXcode.installBoth(in: apps) }
        if let pin { project.write(pin, to: ".xcode-version") }
        if let workflow { project.write(workflow, to: ".github/workflows/ci.yml") }
        var responses = FakeSession.responses(serving: server == nil ? nil : project, age: server ?? "", programs: running.map { [202: "\(apps.path)/\($0)/Contents/MacOS/Xcode"] } ?? [:])
        responses["xcode-select -p"] = .init(status: 0, stdout: "\(apps.path)/Xcode-27.2.0-Beta.3.app/Contents/Developer\n")
        let context = CheckContext.fake(FakeRunner(installed: xcodesTool ? ["xcodes"] : [], responses: responses), project: project, processID: FakeSession.doctor, applications: apps)
        if let launch {
            let record = Xcodes.launchRecord(of: project, on: context.machine)
            try! FileManager.default.createDirectory(at: record.deletingLastPathComponent(), withIntermediateDirectories: true)
            try! launch.replacingOccurrences(of: "APPS", with: apps.path).write(to: record, atomically: true, encoding: .utf8)
            try! FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -recorded)], ofItemAtPath: record.path)
        }
        return context
    }

    /// No MobileBuildMCP serves the project, as from a terminal before a session: nothing has had the pin to apply.
    @Test func withoutAServerThePinWaitsForItsStart() async {
        let result = await XcodePinCheck().run(context(pin: "26.4\n", server: nil))
        #expect(result == .skip("MobileBuildMCP isn't running for this project; it starts with Xcode 26.4"))
    }

    /// A record older than the running server is an earlier start's: this one started without the pin.
    @Test func aRecordOlderThanTheServerIsAnEarlierStarts() async {
        let result = await XcodePinCheck().run(context(pin: "26.4\n", launch: "applied APPS/Xcode-26.4.app/Contents/Developer\n", recorded: 3_600))
        #expect(result.status == .warn)
        #expect(result.message.contains("started without it (it started before the pin applied)"))
    }

    @Test func aCLIThatFailedIsSaidToHaveFailed() async {
        let result = await XcodePinCheck().run(context(pin: "26.4\n", launch: "failed 1\n"))
        #expect(result.message.contains("started without it (the xcrew CLI failed, with status 1)"))
    }

    /// A CI matrix over several Xcodes is fine when the project's is among them.
    @Test func aCIMatrixWithTheProjectsXcodePasses() async {
        let matrix = "jobs:\n  test:\n    strategy:\n      matrix:\n        include:\n          - xcode-version: '26.4'\n          - xcode-version: '27.2'\n"
        #expect(await XcodeCICheck().run(context(pin: "26.4\n", workflow: matrix)).status == .pass)
    }

    /// setup-xcode reads `26` as the newest 26.x: a partial version covers the project's.
    @Test func aPartialCIVersionCoversTheProjects() async {
        let partial = "jobs:\n  test:\n    steps:\n      - uses: maxim-lobanov/setup-xcode@v1\n        with:\n          xcode-version: '26'\n"
        #expect(await XcodeCICheck().run(context(pin: "26.4\n", workflow: partial)).status == .pass)
    }

    /// Without a pin, CI already on the Xcode builds use has nothing to ask for.
    @Test func withoutAPinCIOnTheBuildsXcodeAsksNothing() async {
        let on27 = "jobs:\n  test:\n    steps:\n      - uses: maxim-lobanov/setup-xcode@v1\n        with:\n          xcode-version: '27.2'\n"
        #expect(await XcodePinCheck().run(context(workflow: on27)).status == .pass)
    }

    static let ciOn26_3 = "jobs:\n  test:\n    steps:\n      - uses: maxim-lobanov/setup-xcode@v1\n        with:\n          xcode-version: '26.3'\n"

    /// Another major is another SDK and compiler, so a build may fail where CI's pass, but the Mac still builds: a warning.
    @Test func aPinOfAnotherMajorWarnsThatTheBuildMayFail() async {
        let result = await XcodePinCheck().run(context(pin: "25.0\n", xcodesTool: true))
        #expect(result == .warn("builds use Xcode 27.2 while the project pins Xcode 25.0 (.xcode-version), and a build may fail with another major version's SDK: xcodes install 25.0"))
    }

    func pinNote(_ context: CheckContext, fixture: String, server: Server = .mobileBuildMCP, kind: Report.Kind = .build, isError: Bool = true) async throws -> String? {
        let text = try String(contentsOf: try #require(Bundle.module.url(forResource: fixture, withExtension: "txt", subdirectory: "Fixtures/Reports")), encoding: .utf8)
        let report = await Report.make(kind: kind, output: ToolOutput(text: text, server: server, isError: isError), home: "/home", runner: context.runner, project: context.project, machine: context.machine)
        return report.notes.first { $0.contains("(.xcode-version)") }
    }

    /// A failed MobileBuildMCP build or test in a project whose pin isn't the Xcode building says it may be the cause,
    /// in the check's own words and with its fix; a pass says nothing, nor a failure built with the pinned Xcode.
    @Test func aFailureWithAnotherXcodeThanThePinSaysItMayBeTheCause() async throws {
        let mismatched = context(pin: "25.0\n")
        #expect(try await pinNote(mismatched, fixture: "mobileBuildFailed") == "xcrew: builds use Xcode 27.2 while the project pins Xcode 25.0 (.xcode-version): a different SDK may be the cause. To build with the pin, install Xcode 25.0 from https://developer.apple.com/download/all/")
        #expect(try await pinNote(mismatched, fixture: "mobileBuildPassed", isError: false) == nil)
        #expect(try await pinNote(context(pin: "27.2\n", server: nil), fixture: "mobileBuildFailed") == nil)
    }

    /// A run builds first unless it only launches, and fails the same way.
    @Test func aFailedRunGetsTheNoteToo() async throws {
        #expect(try await pinNote(context(pin: "25.0\n"), fixture: "mobileBuildFailed", kind: .run) != nil)
    }

    /// The Xcode MCP builds with whichever Xcode is open, which isn't what the pin decides.
    @Test func anXcodeMCPFailureGetsNoNote() async throws {
        #expect(try await pinNote(context(pin: "25.0\n"), fixture: "xcodeBuildFailed", server: .xcode) == nil)
    }

    /// The pin is installed but MobileBuildMCP started without it: the note says so, and the fix is a restart.
    @Test func aServerStartedWithoutThePinSaysToRestart() async throws {
        let note = try await pinNote(context(pin: "26.4\n", launch: "timed out 30\n"), fixture: "mobileBuildFailed")
        #expect(note == "xcrew: MobileBuildMCP started without the project's pin, Xcode 26.4 (.xcode-version), so it builds with Xcode 27.2: a different SDK may be the cause. Restart Claude Code to build with the pin.")
    }

    /// Which Xcode builds is the person's choice: a pin no installed Xcode matches stays off the line above the prompt,
    /// but a pin the server failed to start with is a fault with a fix, and shows there.
    @Test func onlyAPinTheServerFailedToApplyShowsAtThePrompt() async {
        #expect(await XcodePinCheck().run(context(pin: "25.0\n")).isOffThePrompt)
        #expect(!(await XcodePinCheck().run(context(pin: "26.4\n", launch: "timed out 30\n")).isOffThePrompt))
    }

    /// A minor or patch apart rarely changes a build; it matters for matching CI's diagnostics.
    @Test func aPinOfTheSameMajorNoInstalledXcodeMatchesWarns() async {
        let result = await XcodePinCheck().run(context(pin: "27.1\n", xcodesTool: true))
        #expect(result == .warn("builds use Xcode 27.2 while the project pins Xcode 27.1 (.xcode-version); a minor or patch difference rarely matters except to match CI's diagnostics: optionally, xcodes install 27.1"))
    }

    /// An older toolchain can lack the pinned SDK's APIs, so a newer pin says the build may fail, as a warning.
    @Test func aPinNewerThanTheBuildsXcodeWarnsThatTheBuildMayFail() async {
        let result = await XcodePinCheck().run(context(pin: "27.3\n", xcodesTool: true))
        #expect(result == .warn("builds use Xcode 27.2 while the project pins Xcode 27.3 (.xcode-version), and a build may fail where the code uses the newer SDK: xcodes install 27.3"))
    }

    /// `xcodes` isn't on every Mac: without it the fix is Apple's download page.
    @Test func withoutXcodesTheInstallIsApplesDownloadPage() async {
        let other = await XcodePinCheck().run(context(pin: "25.0\n"))
        #expect(other.status == .warn)
        #expect(other.message.hasSuffix(": install Xcode 25.0 from https://developer.apple.com/download/all/"))
        let same = await XcodePinCheck().run(context(pin: "27.1\n"))
        #expect(same.message.hasSuffix(": optionally, install Xcode 27.1 from https://developer.apple.com/download/all/"))
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
