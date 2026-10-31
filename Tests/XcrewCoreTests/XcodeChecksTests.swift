import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// The doctor on which Xcode a session builds with: the project's pin, CI's, and the Xcode the Xcode MCP works through.
@Suite struct XcodeChecksTests {
    /// A project on a Mac with Xcode 26.4 and Xcode 27.2 beta 3, 27.2 selected; this session's MobileBuildMCP serving it,
    /// started `server` ago (`ps`'s `etime`) unless nil; and what the launcher recorded, `launch`, `recorded` seconds ago.
    func context(pin: String? = nil, workflow: String? = nil, running: String? = nil, launch: String? = nil, recorded: TimeInterval = 5, server: String? = "00:30", onlyOne: Bool = false, xcodesTool: Bool = false, mcpStatus: String? = nil) -> CheckContext {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        let apps = project.root.appending(path: "Applications")
        if onlyOne { FakeXcode.install(in: apps, "Xcode-27.2.0-Beta.3.app", version: "27.2", build: "27B5038j") } else { FakeXcode.installBoth(in: apps) }
        if let pin { project.write(pin, to: ".xcode-version") }
        if let workflow { project.write(workflow, to: ".github/workflows/ci.yml") }
        var responses = FakeSession.responses(serving: server == nil ? nil : project, age: server ?? "", programs: running.map { [202: "\(apps.path)/\($0)/Contents/MacOS/Xcode"] } ?? [:])
        responses["xcode-select -p"] = .init(status: 0, stdout: "\(apps.path)/Xcode-27.2.0-Beta.3.app/Contents/Developer\n")
        if let mcpStatus { responses["xcrun mcp-server status"] = .init(status: 0, stdout: mcpStatus) }
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

    /// A failed build's text, with one error.
    static func buildFailure(_ error: String) -> String {
        "\n🔨 Build\n\nErrors (1):\n\n  ✗ \(error)\n    /Users/dev/App/Sources/App.swift:2\n\n❌ Build failed. (⏱️ 3.2s)"
    }

    /// A failed build whose error is one a different SDK or toolchain gives: a module compiled by another Swift.
    static let toolchainFailure = buildFailure("module compiled with Swift 6.1 cannot be imported by the Swift 6.3 compiler: /Users/dev/DerivedData/Build/Products/Debug-iphonesimulator/Core.swiftmodule")

    static func fixture(_ name: String) -> String {
        try! String(contentsOf: Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures/Reports")!, encoding: .utf8)
    }

    func pinNote(_ context: CheckContext, text: String = toolchainFailure, server: Server = .mobileBuildMCP, kind: Report.Kind = .build, isError: Bool = true) async throws -> String? {
        let report = await Report.make(kind: kind, output: ToolOutput(text: text, server: server, isError: isError), home: context.machine.home.path, runner: context.runner, project: context.project, machine: context.machine)
        // The pin's note travels apart from the notes, for the mod to show once a session.
        #expect(!report.notes.contains { $0.contains("(.xcode-version)") })
        return report.pinNote
    }

    /// A failed MobileBuildMCP build or test in a project whose pin isn't the Xcode building says it may be the cause,
    /// in the check's own words and with its fix; a failure built with the pinned Xcode says nothing.
    @Test func aFailureWithAnotherXcodeThanThePinSaysItMayBeTheCause() async throws {
        let mismatched = context(pin: "25.0\n")
        #expect(try await pinNote(mismatched) == "xcrew: builds use Xcode 27.2 while the project pins Xcode 25.0 (.xcode-version): a different SDK may be the cause. To build with the pin, install Xcode 25.0 from https://developer.apple.com/download/all/")
        #expect(try await pinNote(context(pin: "27.2\n", server: nil)) == nil)
    }

    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aPassWithAnotherXcodeThanThePinSaysNothing() async throws {
        #expect(try await pinNote(context(pin: "25.0\n"), text: Raw.text("build_sim"), isError: false) == nil)
    }

    /// The pin is named only where another SDK or toolchain may be the cause: a type error in a line just written, a
    /// test's failed assertion, or a run that succeeded with no tests, says nothing of it.
    /// The run that succeeded is marked an error here, so it's the errors, not the outcome, that keep the pin out.
    @Test(arguments: [
        (fixture("mobileBuildFailed"), Report.Kind.build),
        (fixture("mobileTestsFailed"), .test),
        ("\n🧪 Test\n\n✅ Test succeeded. (⏱️ 3.4s)\n  └ Files:\n     └── ~/Library/Developer/MobileBuildMCP/workspaces/App-0000/logs/test_sim.log — Build Logs", .test),
    ])
    func aFailureOfTheCodeSaysNothingOfThePin(_ text: String, kind: Report.Kind) async throws {
        #expect(try await pinNote(context(pin: "25.0\n"), text: text, kind: kind) == nil)
    }

    /// The errors another SDK or toolchain gives: a module another Swift compiled, a deployment target or SDK the
    /// toolchain doesn't support, a platform it doesn't know.
    @Test(arguments: [
        "module compiled with Swift 6.1 cannot be imported by the Swift 6.3 compiler: /Users/dev/Core.swiftmodule",
        "The iOS Simulator deployment target 'IPHONEOS_DEPLOYMENT_TARGET' is set to 11.0, but the range of supported deployment target versions is 12.0 to 27.2.99.",
        "SDK \"iphonesimulator26.5\" cannot be located.",
        "unrecognized platform name 'visionOS'",
    ])
    func anSDKOrToolchainErrorNamesThePin(_ error: String) async throws {
        #expect(try await pinNote(context(pin: "25.0\n"), text: Self.buildFailure(error)) != nil)
    }

    /// A test run whose build failed lists only that it couldn't build; the compiler's error is in the build log it names,
    /// and that's where the pin's cause shows.
    @Test func aTestRunsBuildLogErrorNamesThePin() async throws {
        let mismatched = context(pin: "25.0\n")
        let log = mismatched.machine.home.appending(path: "Library/Developer/MobileBuildMCP/workspaces/sample-0000/logs/test_sim.log")
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "/Users/dev/App/Sources/App.swift:2:8: error: module compiled with Swift 6.1 cannot be imported by the Swift 6.3 compiler: /Users/dev/Core.swiftmodule\n".write(to: log, atomically: true, encoding: .utf8)
        #expect(try await pinNote(mismatched, text: Self.fixture("mobileTestsBuildFailed"), kind: .test) != nil)
        try "/Users/dev/App/Sources/App.swift:2:8: error: cannot convert value of type 'String' to specified type 'Int'\n".write(to: log, atomically: true, encoding: .utf8)
        #expect(try await pinNote(mismatched, text: Self.fixture("mobileTestsBuildFailed"), kind: .test) == nil)
    }

    /// The code's own errors that mention an SDK, a deployment target or availability: the pin isn't their cause.
    @Test(arguments: [
        "'navigationTransition' is only available in iOS 26.0 or newer",
        "Crashlytics SDK: missing GoogleService-Info.plist",
        "cannot find 'SDK' in scope",
        "compiling for iOS 15.0, but module 'Charts' has a minimum deployment target of iOS 16.0: /Users/dev/Charts.swiftmodule",
    ])
    func theCodesOwnErrorSaysNothingOfThePin(_ error: String) async throws {
        #expect(try await pinNote(context(pin: "25.0\n"), text: Self.buildFailure(error)) == nil)
    }

    /// Only a test run whose build failed reads the build log: a failed test's log holds the app's own output.
    @Test func aFailedTestsBuildLogIsntRead() async throws {
        let mismatched = context(pin: "25.0\n")
        let log = mismatched.machine.home.appending(path: "Library/Developer/MobileBuildMCP/workspaces/sample-0000/logs/test_sim.log")
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "network error: SDK \"iphonesimulator26.5\" cannot be located.\n".write(to: log, atomically: true, encoding: .utf8)
        #expect(try await pinNote(mismatched, text: Self.fixture("mobileTestsFailed"), kind: .test) == nil)
    }

    /// The report names the pin its note is about, for the mod to name each pin once a session.
    @Test func theReportNamesThePinItsNoteIsAbout() async throws {
        let context = context(pin: "25.0\n")
        let report = await Report.make(kind: .build, output: ToolOutput(text: Self.toolchainFailure, server: .mobileBuildMCP, isError: true), home: context.machine.home.path, runner: context.runner, project: context.project, machine: context.machine)
        #expect(report.pin == "25.0 (.xcode-version)")
    }

    /// A run builds first unless it only launches, and fails the same way.
    @Test func aFailedRunGetsTheNoteToo() async throws {
        #expect(try await pinNote(context(pin: "25.0\n"), kind: .run) != nil)
    }

    /// The Xcode MCP builds with whichever Xcode is open, which isn't what the pin decides.
    @Test func anXcodeMCPFailureGetsNoNote() async throws {
        #expect(try await pinNote(context(pin: "25.0\n"), text: Self.fixture("xcodeBuildFailed"), server: .xcode) == nil)
    }

    /// The pin is installed but MobileBuildMCP started without it: the note says so, and the fix is a restart.
    @Test func aServerStartedWithoutThePinSaysToRestart() async throws {
        let note = try await pinNote(context(pin: "26.4\n", launch: "timed out 30\n"))
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

    /// The headless Xcode MCP serves with no Xcode window open, and runs no Xcode app the process list shows.
    @Test func noOpenXcodeWithTheHeadlessMCPSaysItIsEnabled() async {
        let result = await XcodeOpenCheck().run(context(mcpStatus: "Permission: enabled\nApproved agents:\n  com.anthropic.claude-code\n"))
        #expect(result == .pass("no Xcode window is open; the headless Xcode MCP is enabled"))
    }
}

/// The handshake with a fresh `xcrun mcpbridge`: MCP's `initialize`, which the bridge answers without asking Xcode for
/// approval, run only under a Claude Code session, whose agent Xcode already permits.
@Suite struct XcodeMCPHandshakeCheckTests {
    static let command = XcodeMCPHandshakeCheck.command.joined(separator: " ")
    static let answer = #"{"id":1,"jsonrpc":"2.0","result":{"capabilities":{"tools":{"listChanged":true}},"instructions":"Request Xcode perform the action you specify.","protocolVersion":"2025-06-18","serverInfo":{"name":"xcode-tools","version":"25464"}}}"# + "\n"

    func context(_ bridge: CommandResult?, inSession: Bool = true) -> CheckContext {
        var responses = FakeSession.responses(serving: nil)
        if let bridge { responses[Self.command] = bridge }
        return CheckContext.fake(FakeRunner(responses: responses), processID: inSession ? FakeSession.doctor : 999)
    }

    @Test func aBridgeThatAnswersPasses() async {
        #expect(await XcodeMCPHandshakeCheck().run(context(.init(status: 0, stdout: Self.answer))) == .pass("a new Xcode MCP bridge answers: xcode-tools 25464"))
    }

    @Test func aBridgeThatDoesNotAnswerFails() async {
        #expect(await XcodeMCPHandshakeCheck().run(context(.init(status: 1, stdout: ""))) == .fail("a new Xcode MCP bridge (xcrun mcpbridge) didn't answer MCP's initialize: xcrun mcp-server status says whether the server is on, and /mcp → Reconnect restarts this session's"))
    }

    /// From a terminal the bridge's first call may ask Xcode to approve a new agent: the doctor never raises that dialog.
    @Test func outsideASessionItSkips() async {
        #expect(await XcodeMCPHandshakeCheck().run(context(nil, inSession: false)) == .skip("runs only from a Claude Code session, whose agent Xcode already permits"))
    }

    /// It starts a server, so the doctor the line above the prompt runs leaves it out; the full doctor runs it.
    @Test func onlyTheFullDoctorRunsIt() {
        #expect(Doctor.checks.filter(\.startsAServer).map(\.id) == ["xcode-mcp/handshake"])
    }
}
