import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

@Suite struct HookTests {
    @Test func readsTheEventItNeeds() async {
        let event = HookEvent(json: Data(#"{"hook_event_name":"SessionStart","cwd":"/work/App","source":"startup"}"#.utf8))
        #expect(event == HookEvent(name: "SessionStart", cwd: "/work/App"))
        #expect(HookEvent(json: Data("not json".utf8)).name == "SessionStart")
    }

    @Test func replyShape() async throws {
        let json = HookReply(event: HookEvent(name: "SessionStart"), context: "rules").json
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let specific = try #require(object["hookSpecificOutput"] as? [String: String])
        #expect(specific == ["hookEventName": "SessionStart", "additionalContext": "rules"])
    }

    @Test func briefingOnlyInAppleProjects() async {
        let elsewhere = SessionBriefing(project: .temporary(), machine: CheckContext.fake().machine)
        #expect(await elsewhere.text(routing: "rules") == nil)

        let project = Project.temporary(containing: ["App.xcodeproj"])
        let text = await SessionBriefing(project: project, machine: CheckContext.fake(project: project).machine).text(routing: "rules\n")
        #expect(text?.hasPrefix("rules\n- **xcrew:** MobileBuildMCP isn't usable here (not installed") == true)
        #expect(text?.contains("/xcrew:setup") == true)
    }

    /// Claude learns the profiles this config defines, not a fixed list that may name ones it lacks.
    @Test func briefingNamesTheConfiguredProfiles() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write(ConfigRenderer.render(.init(container: "App.xcodeproj", testSimulator: "iPhone 17", appScheme: "App", testScheme: "App"), root: project.root), to: ".mobilebuildmcp/config.yaml")
        let text = await SessionBriefing(project: project, machine: Self.machine(project, version: "2.7.1")).text(routing: "rules\n")
        #expect(text?.contains("- **xcrew:** MobileBuildMCP profiles here: `unit` (active), `app`. Switch with `session_use_defaults_profile`.") == true)
    }

    /// A scheme whose test plan runs its tests under several configurations is named with them, so Claude knows a test
    /// can fail under one and pass under another; a plan with one configuration isn't.
    @Test func briefingNamesATestPlansConfigurations() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.writeScheme("App", plan: "App.xctestplan")
        project.write(#"{"configurations":[{"id":"1","name":"Light","options":{}},{"id":"2","name":"Dark","options":{}}],"defaultOptions":{},"testTargets":[],"version":1}"#, to: "App.xctestplan")
        project.writeScheme("Other", plan: "One.xctestplan")
        project.write(#"{"configurations":[{"id":"1","name":"Only","options":{}}],"defaultOptions":{},"testTargets":[],"version":1}"#, to: "One.xctestplan")
        let text = await SessionBriefing(project: project, machine: Self.machine(project, version: "2.7.1")).text(routing: "rules\n")
        #expect(text?.contains("- **xcrew:** Test plan `App`, the default of scheme `App`, runs each test under each of its configurations: Light and Dark. A test can fail under one and pass under another; `look` names which.") == true, "\(text ?? "")")
        #expect(text?.contains("`Other`") == false)
    }

    /// One line per test plan, whichever schemes share it, and a few plans at most: a large modular app's schemes would
    /// otherwise each add one.
    @Test func briefingNamesEachTestPlanOnceAndAFewAtMost() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        for scheme in ["A", "B", "C"] { project.writeScheme(scheme, plan: "Shared.xctestplan") }
        for plan in 1...6 {
            project.writeScheme("P\(plan)", plan: "P\(plan).xctestplan")
            project.write(#"{"configurations":[{"name":"Light"},{"name":"Dark"}],"testTargets":[],"version":1}"#, to: "P\(plan).xctestplan")
        }
        project.write(#"{"configurations":[{"name":"Light"},{"name":"Dark"}],"testTargets":[],"version":1}"#, to: "Shared.xctestplan")
        let notes = (await SessionBriefing(project: project, machine: Self.machine(project, version: "2.7.1")).text(routing: "rules\n") ?? "").components(separatedBy: "\n").filter { $0.contains("Test plan") || $0.contains("test plans") }
        // In the order the schemes sort: `Shared` comes with `A`.
        #expect(notes.first == "- **xcrew:** Test plan `Shared`, the default of schemes `A`, `B` and `C`, runs each test under each of its configurations: Light and Dark. A test can fail under one and pass under another; `look` names which.", "\(notes)")
        #expect(notes.contains("- **xcrew:** Test plan `P1`, the default of scheme `P1`, runs each test under each of its configurations: Light and Dark. A test can fail under one and pass under another; `look` names which."), "\(notes)")
        #expect(notes.count == 6, "\(notes)")
        #expect(notes.last == "- **xcrew:** and 2 more test plans run each test under several configurations.", "\(notes)")
    }

    /// MobileBuildMCP writes a config of its own when Claude saves session defaults: one without a profile naming a
    /// scheme still asks for setup.
    @Test func briefingOffersSetupWhileNoProfileNamesAScheme() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write("schemaVersion: 1\nsessionDefaults:\n  workspacePath: ./App.xcodeproj\n", to: ".mobilebuildmcp/config.yaml")
        let text = await SessionBriefing(project: project, machine: Self.machine(project, version: "2.7.1")).text(routing: "rules\n")
        #expect(text?.contains("- **xcrew:** MobileBuildMCP has no scheme to build this project with yet: before the first build or test, offer `/xcrew:setup`, which writes its profiles once from the project's schemes and simulators.") == true)
    }

    @Test func briefingWithAProfileThatNamesASchemeOffersNoSetup() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write(ConfigRenderer.render(.init(container: "App.xcodeproj", testSimulator: "iPhone 17", testScheme: "AppTests"), root: project.root), to: ".mobilebuildmcp/config.yaml")
        let text = await SessionBriefing(project: project, machine: Self.machine(project, version: "2.7.1")).text(routing: "rules\n")
        #expect(text?.contains("/xcrew:setup") == false)
    }

    /// The project card the mod saved for this folder and the branch checked out comes last, so it reaches Claude after a
    /// /clear or a compaction as well, which start the hook again.
    @Test func briefingEndsWithTheProjectCardForThisBranch() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        let machine = Self.machine(project, version: "2.7.1", branch: "feat/card")
        ProjectCard.save(.init(folder: project.canonicalRoot, branch: "feat/card", updated: Date().timeIntervalSince1970 * 1000 - 5 * 60_000, text: "Notes:\n- a"), on: machine)
        let text = await SessionBriefing(project: project, machine: machine).text(routing: "rules\n")
        #expect(text?.hasSuffix("\n\nNotes, as of the run 5 min ago:\n- a") == true)
    }

    /// A project that pins its Xcode says so, and that the Xcode MCP works through the open one, which no pin changes; it
    /// states the fact and never steers the person to another Xcode.
    @Test func briefingNamesThePinnedXcode() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write("26.4\n", to: ".xcode-version")
        let text = await SessionBriefing(project: project, machine: Self.machine(project, version: "2.7.1")).text(routing: "rules\n")
        #expect(text?.contains("- **xcrew:** This project pins Xcode 26.4 (`.xcode-version`). MobileBuildMCP starts with it when it's installed and xcrew's CLI is ready, and `xcrew doctor` says when it didn't. The Xcode MCP works through whichever Xcode is open.") == true)
    }

    /// `simctl list devices booted` filters on each device's description, so a shut-down device whose name holds the word
    /// is listed too; only its `state` says.
    static let booted = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-2":[{"udid":"A1","state":"Booted","name":"iPhone 17","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17"},{"udid":"B2","state":"Shutdown","name":"Booted Test Phone","isAvailable":true}],"com.apple.CoreSimulator.SimRuntime.iOS-26-4":[{"udid":"C3","state":"Booted","name":"iPad Air 11-inch (M3)","isAvailable":true}]}}"#

    static let coreSimulatorRuns = ["pgrep -x com.apple.CoreSimulator.CoreSimulatorService": CommandResult(status: 0, stdout: "2216\n")]

    @Test func theBootedSimulatorsAreTheOnesBootedOrBootingNow() async {
        let listed = Self.booted.replacingOccurrences(of: #""udid":"C3","state":"Booted""#, with: #""udid":"C3","state":"Booting""#)
        let runner = FakeRunner(responses: ["xcrun simctl list devices booted --json": .init(status: 0, stdout: listed)])
        let booted = await SimulatorCatalog.booted(using: runner, timeout: .seconds(1))
        #expect(booted.map(\.name) == ["iPad Air 11-inch (M3)", "iPhone 17"])
        #expect(await SimulatorCatalog.booted(using: FakeRunner(), timeout: .seconds(1)).isEmpty)
    }

    @Test func briefingNamesTheBootedSimulatorsWhenThereAreAny() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        let listed = Self.booted.replacingOccurrences(of: #""udid":"C3","state":"Booted""#, with: #""udid":"C3","state":"Booting""#)
        let runner = FakeRunner(responses: Self.coreSimulatorRuns.merging(["xcrun simctl list devices booted --json": .init(status: 0, stdout: listed)]) { $1 })
        let text = await SessionBriefing(project: project, machine: CheckContext.fake(runner, project: project).machine).text(routing: "rules\n")
        #expect(text?.contains("- **xcrew:** Simulators booted now: iPad Air 11-inch (M3) (iOS 26.4, C3, booting), iPhone 17 (iOS 27.2, A1). Reuse one rather than booting another.") == true)
    }

    /// Only a running CoreSimulator service has simulators booted; `xcrun` without it starts one, or offers to install
    /// the developer tools on a Mac without them.
    @Test func briefingAsksSimctlOnlyWhileCoreSimulatorRuns() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        let runner = FakeRunner(responses: ["xcrun simctl list devices booted --json": .init(status: 0, stdout: Self.booted)])
        let text = await SessionBriefing(project: project, machine: CheckContext.fake(runner, project: project).machine).text(routing: "rules\n")
        #expect(text?.contains("Simulators booted now") == false)
    }

    @Test func briefingForAnAppInASubfolder() async {
        let project = Project.temporary(containing: [".git", "ios/Tuist.swift"])
        let text = await SessionBriefing(project: project, machine: CheckContext.fake(project: project).machine).text(routing: "rules\n")
        #expect(text?.hasPrefix("rules\n- **xcrew:** MobileBuildMCP isn't usable here (not installed") == true)
    }

    @Test func generatedProjectsCountBeforeTheirWorkspaceExists() async {
        let project = Project.temporary()
        project.write("", to: "Project.swift")
        #expect(project.isApplePlatformProject)
    }

    // MARK: Failover to the Xcode MCP

    static let failover = "Until it is, the routing rules' MobileBuildMCP rows don't apply: build with the Xcode MCP's `BuildProject` and test with `RunAllTests`. They work through Xcode itself, on the open project, its active scheme and destination, in Xcode's own DerivedData. Lost meanwhile: coverage reports, simulator control, UI automation and LLDB. Tell the person once that MobileBuildMCP is unavailable and what that loses, then carry on. If a build or test needs a scheme other than Xcode's active one, ask before switching it: that changes their open Xcode. If the Xcode MCP's tools refuse too, run `xcrew doctor`."

    /// A Mac whose `mobilebuildmcp` is a real file, answering `--version` with `version` (nil: no answer). The file is
    /// written once, since the version's cache is keyed by its modification time.
    static func machine(_ project: Project, version: String?, branch: String? = nil) -> Machine {
        if !FileManager.default.fileExists(atPath: project.root.appending(path: "bin/mobilebuildmcp").path) { project.write("#!/bin/sh\n", to: "bin/mobilebuildmcp") }
        var runner = FakeRunner(installed: ["mobilebuildmcp"], responses: version.map { ["mobilebuildmcp --version": CommandResult(status: 0, stdout: $0 + "\n")] } ?? [:])
        if let branch { runner.responses["git -C \(project.root.path) symbolic-ref --short -q HEAD"] = CommandResult(status: 0, stdout: branch + "\n") }
        runner.paths["mobilebuildmcp"] = project.root.appending(path: "bin/mobilebuildmcp").path
        return CheckContext.fake(runner, project: project).machine
    }

    @Test func aMissingMobileBuildMCPSendsBuildsAndTestsToTheXcodeMCP() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        let text = await SessionBriefing(project: project, machine: CheckContext.fake(project: project).machine).text(routing: "rules\n") ?? ""
        #expect(text.contains("- **xcrew:** MobileBuildMCP isn't usable here (not installed: ask the person to run `brew install getsentry/xcodebuildmcp/mobilebuildmcp`, then restart Claude Code), so its build and test tools aren't either. \(Self.failover)"))
    }

    @Test func anOutdatedMobileBuildMCPSendsThemThereToo() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        let text = await SessionBriefing(project: project, machine: Self.machine(project, version: "2.7.0")).text(routing: "rules\n") ?? ""
        #expect(text.contains("MobileBuildMCP isn't usable here (version 2.7.0 is older than 2.7.1: ask the person to run `brew upgrade mobilebuildmcp`, then restart Claude Code), so its build and test tools aren't either. \(Self.failover)"))
    }

    /// While MobileBuildMCP can't serve, its profiles aren't offered: switching them would call tools that aren't there.
    @Test func theProfilesAreLeftOutWhileItCantServe() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write(ConfigRenderer.render(.init(container: "App.xcodeproj", testSimulator: "iPhone 17", appScheme: "App", testScheme: "App"), root: project.root), to: ".mobilebuildmcp/config.yaml")
        let text = await SessionBriefing(project: project, machine: CheckContext.fake(project: project).machine).text(routing: "rules\n") ?? ""
        #expect(text.contains("isn't usable here"))
        #expect(!text.contains("session_use_defaults_profile"))
    }

    /// A version that couldn't be read says nothing about the server, which may well be running: no failover then.
    @Test func anUnreadableVersionKeepsTheRouting() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        let text = await SessionBriefing(project: project, machine: Self.machine(project, version: nil)).text(routing: "rules\n") ?? ""
        #expect(!text.contains("isn't usable"))
    }

    @Test func aUsableMobileBuildMCPLeavesTheRoutingAsItIs() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        let text = await SessionBriefing(project: project, machine: Self.machine(project, version: "2.7.1")).text(routing: "rules\n") ?? ""
        #expect(!text.contains("isn't usable"))
    }

    /// The doctor and the briefing read one assessment: a version the briefing fails over for is one the doctor fails.
    @Test(arguments: ["2.7.0", "2.7.1"])
    func theDoctorAndTheBriefingAgree(_ version: String) async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        let machine = Self.machine(project, version: version)
        let check = await MobileBuildMCPVersionCheck().run(CheckContext(project: project, machine: machine))
        let briefing = await SessionBriefing(project: project, machine: machine).text(routing: "rules\n") ?? ""
        #expect((check.status == .pass) == !briefing.contains("isn't usable"))
    }

    @Test func theDoctorSaysWhenTheVersionCantBeRead() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        let check = await MobileBuildMCPVersionCheck().run(CheckContext(project: project, machine: Self.machine(project, version: nil)))
        #expect(check == .fail("its version couldn't be read: brew reinstall mobilebuildmcp"))
    }

    /// The version is read from the cache while the binary is unchanged: the briefing runs no `--version` then.
    @Test func aWarmCacheAnswersWithoutRunningMobileBuildMCP() async throws {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        let warm = Self.machine(project, version: "2.7.1")
        #expect(await MobileBuildMCPStatus.assess(warm) == .usable(version: "2.7.1"))
        let cold = Self.machine(project, version: nil)
        #expect(await MobileBuildMCPStatus.assess(cold) == .usable(version: "2.7.1"))
    }
}
