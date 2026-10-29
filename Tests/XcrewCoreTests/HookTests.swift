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
        #expect(text?.hasPrefix("rules\n- **xcrew:** MobileBuildMCP isn't installed") == true)
        #expect(text?.contains("/xcrew:setup") == true)
    }

    /// Claude learns the profiles this config defines, not a fixed list that may name ones it lacks.
    @Test func briefingNamesTheConfiguredProfiles() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write(ConfigRenderer.render(.init(container: "App.xcodeproj", testSimulator: "iPhone 17", appScheme: "App", testScheme: "App"), root: project.root), to: ".mobilebuildmcp/config.yaml")
        let text = await SessionBriefing(project: project, machine: CheckContext.fake(project: project).machine).text(routing: "rules\n")
        #expect(text?.contains("- **xcrew:** MobileBuildMCP profiles here: `unit` (active), `app`. Switch with `session_use_defaults_profile`.") == true)
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
        #expect(text?.hasPrefix("rules\n- **xcrew:** MobileBuildMCP isn't installed") == true)
    }

    @Test func generatedProjectsCountBeforeTheirWorkspaceExists() async {
        let project = Project.temporary()
        project.write("", to: "Project.swift")
        #expect(project.isApplePlatformProject)
    }
}
