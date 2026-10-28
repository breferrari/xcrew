import Foundation
import Testing
import XcrewCore
import XcrewTestSupport

@Suite struct CLITests {
    @Test func helpListsEveryCommand() async {
        let run = await Run("help")
        #expect(run.status == 0)
        for name in ["setup", "doctor", "repair-macros", "xcode-skills", "hook"] {
            #expect(run.text.contains("  \(name)"))
        }
    }

    @Test func unknownCommandIsAUsageError() async {
        let run = await Run("frobnicate")
        #expect(run.status == 64)
        #expect(run.errors == ["unknown command 'frobnicate' (xcrew help)"])
    }

    @Test func optionWithoutValueIsAUsageError() async {
        #expect(await Run("setup", "--container").status == 64)
    }
}

@Suite struct SetupCommandTests {
    let simulators = FakeRunner(responses: [
        "xcrun simctl list devices available --json": .init(status: 0, stdout: #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone 18","isAvailable":true}]}}"#),
    ])

    func config(_ project: Project) -> String {
        (try? String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8)) ?? ""
    }

    @Test func detectsTheWorkspaceAndTheNewestIPhone() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        let run = await Run("setup", context: .fake(simulators, project: project))
        #expect(run.status == 0)
        #expect(config(project).contains("workspacePath: '\(project.root.path)/App.xcworkspace'"))
        #expect(config(project).contains("simulatorName: 'iPhone 18'"))
    }

    @Test func mcsAnswersFillWhatOptionsLeaveOut() async {
        let project = Project.temporary(containing: ["App.xcworkspace", "Other.xcworkspace"])
        let environment = ["MCS_RESOLVED_PROJECT": "./Other.xcworkspace", "MCS_RESOLVED_APP_SCHEME": "App", "MCS_RESOLVED_TEST_SIMULATOR": ""]
        let run = await Run("setup", "--test-simulator", "iPhone 17", context: .fake(simulators, project: project, environment: environment))
        #expect(run.status == 0)
        #expect(config(project).contains("Other.xcworkspace"))
        #expect(config(project).contains("simulatorName: 'iPhone 17'"))
        #expect(config(project).contains("  app:\n"))
    }

    @Test func optionsWinOverMCSAnswers() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        let run = await Run("setup", "--test-simulator", "iPhone 17", context: .fake(simulators, project: project, environment: ["MCS_RESOLVED_TEST_SIMULATOR": "iPhone 9"]))
        #expect(run.status == 0)
        #expect(config(project).contains("'iPhone 17'"))
    }

    @Test func noContainerIsAUsageError() async {
        let run = await Run("setup", context: .fake(simulators))
        #expect(run.status == 64)
        #expect(run.errors.first?.contains("no .xcworkspace or .xcodeproj") == true)
    }

    @Test func noIPhoneIsAUsageError() async {
        let run = await Run("setup", context: .fake(project: .temporary(containing: ["App.xcodeproj"])))
        #expect(run.status == 64)
        #expect(run.errors.first?.contains("no iPhone simulator") == true)
    }

    @Test func inAGitRepositoryTheConfigIsKeptOutOfGit() async throws {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        project.write("", to: ".git/info/exclude")
        var runner = simulators
        runner.responses["git -C \(project.root.path) rev-parse --git-path info/exclude"] = .init(status: 0, stdout: ".git/info/exclude\n")
        let run = await Run("setup", context: .fake(runner, project: project))
        #expect(run.text.contains("kept .mobilebuildmcp/ out of git"))
        #expect(try String(contentsOf: project.root.appending(path: ".git/info/exclude"), encoding: .utf8) == "/.mobilebuildmcp/\n")
    }

    @Test func handWrittenConfigNeedsForce() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        project.write("mine: true\n", to: ".mobilebuildmcp/config.yaml")
        #expect(await Run("setup", context: .fake(simulators, project: project)).text.contains("left as is"))
        #expect(config(project) == "mine: true\n")
        #expect(await Run("setup", "--force", context: .fake(simulators, project: project)).text.contains("kept the old config"))
        #expect(config(project).contains("iPhone 18"))
    }
}

@Suite struct DoctorCommandTests {
    @Test func listNamesEveryCheck() async {
        let run = await Run("doctor", "--list")
        #expect(run.output.count == Doctor.checks.count)
        #expect(run.output.first?.hasPrefix("mobilebuildmcp/version\t") == true)
    }

    @Test func singleCheckExitsWithItsStatus() async {
        let run = await Run("doctor", "--check", "mobilebuildmcp/no-legacy-binary", context: .fake(FakeRunner(installed: ["xcodebuildmcp"])))
        #expect(run.status == 2)
        #expect(run.output.count == 1)
    }

    @Test func unknownCheckIsAUsageError() async {
        #expect(await Run("doctor", "--check", "nope").status == 64)
    }

    @Test func fullRunReportsEveryCheckAndTheWorstStatus() async {
        let run = await Run("doctor")
        #expect(run.output.count == Doctor.checks.count)
        #expect(run.status == CheckStatus.fail.rawValue)
        #expect(run.output.contains { $0.hasPrefix("FAIL  mobilebuildmcp/version") })
    }

    @Test func problemsIsSilentOutsideApplePlatformProjects() async {
        let run = await Run("doctor", "--problems")
        #expect(run.status == 0)
        #expect(run.output.isEmpty)
    }

    @Test func problemsListsOnlyWhatFailedOrWarnedInAnApplePlatformProject() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        let run = await Run("doctor", "--problems", context: .fake(project: project))
        #expect(run.status == 0)
        #expect(!run.output.isEmpty)
        #expect(run.output.allSatisfy { $0.hasPrefix("FAIL  ") || $0.hasPrefix("warn  ") })
        #expect(run.output.contains { $0.hasPrefix("FAIL  mobilebuildmcp/version") })
    }
}

@Suite struct HookCommandTests {
    @Test func sessionStartIsSilentOutsideApplePlatformProjects() async {
        let run = await Run("hook", "session-start", stdin: #"{"hook_event_name":"SessionStart"}"#)
        #expect(run.status == 0)
        #expect(run.output.isEmpty)
    }

    @Test func sessionStartBriefsFromTheRoutingFile() async throws {
        let plugin = Project.temporary()
        plugin.write("## Routing\n", to: "context/routing.md")
        let app = Project.temporary(containing: ["App.xcworkspace"])
        let context = CheckContext.fake(project: app, environment: ["CLAUDE_PLUGIN_ROOT": plugin.root.path])
        let run = await Run("hook", "session-start", context: context, stdin: #"{"hook_event_name":"SessionStart","cwd":"\#(app.root.path)"}"#)
        let reply = try JSONSerialization.jsonObject(with: Data(run.text.utf8)) as? [String: [String: String]]
        #expect(reply?["hookSpecificOutput"]?["additionalContext"]?.hasPrefix("## Routing\n- **xcrew:**") == true)
    }

    @Test func repairIsSilentWhenNothingIsDead() async {
        let run = await Run("hook", "repair-macros", stdin: #"{"hook_event_name":"PostToolUseFailure"}"#)
        #expect(run.status == 0)
        #expect(run.output.isEmpty)
    }

    @Test func unknownHookIsAUsageError() async {
        #expect(await Run("hook", "nope").status == 64)
    }
}

@Suite struct RepairMacrosCommandTests {
    @Test func withNoPluginsThereIsNothingToRepair() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        let run = await Run("repair-macros", context: .fake(project: project))
        #expect(run.status == 0)
        #expect(run.output == ["all 0 macro plugins answer"])
        #expect(await Run("repair-macros", "--check", context: .fake(project: project)).status == 0)
    }
}

@Suite struct XcodeSkillsCommandTests {
    func context(project: Project) -> CheckContext {
        let plugin = Project.temporary()
        plugin.write("# A", to: "skills/swiftui-specialist/SKILL.md")
        let runner = FakeRunner(responses: ["xcrun mcpbridge run-agent plugin path --plugin-format claude": .init(status: 0, stdout: plugin.root.path)])
        return .fake(runner, project: project)
    }

    @Test func listsAndCopies() async {
        let project = Project.temporary()
        #expect(await Run("xcode-skills", "--list", context: context(project: project)).output == ["swiftui-specialist"])
        let run = await Run("xcode-skills", context: context(project: project))
        #expect(run.text == "xcrew: copied 1 Xcode skills into .claude/skills: swiftui-specialist")
        #expect(FileManager.default.fileExists(atPath: project.skillsFolder.appending(path: "swiftui-specialist/SKILL.md").path))
    }

    @Test func withoutXcode27ItSaysWhy() async {
        let run = await Run("xcode-skills")
        #expect(run.status == 64)
        #expect(run.errors.first?.contains("Xcode 27") == true)
    }
}

@Suite struct VersionCommandTests {
    @Test func printsTheVersion() async {
        for flag in ["--version", "version"] {
            let run = await Run(flag)
            #expect(run.status == 0)
            #expect(run.output == ["xcrew \(XcrewVersion.current)"])
        }
    }
}

@Suite struct SetupNextStepTests {
    let simulators = FakeRunner(responses: [
        "xcrun simctl list devices available --json": .init(status: 0, stdout: #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone 18","isAvailable":true}]}}"#),
    ])

    @Test func withoutAnAppSchemeSetupPointsAtTheSkill() async {
        let run = await Run("setup", context: .fake(simulators, project: .temporary(containing: ["App.xcworkspace"])))
        #expect(run.text.contains("/xcrew:setup adds the app and UI-test profiles"))
    }

    @Test func withAnAppSchemeItDoesNot() async {
        let run = await Run("setup", "--app-scheme", "App", context: .fake(simulators, project: .temporary(containing: ["App.xcworkspace"])))
        #expect(!run.text.contains("/xcrew:setup adds"))
    }
}

@Suite struct RepairHookGateTests {
    @Test func anOrdinaryBuildFailureLeavesThePluginsAlone() async {
        // A locator pointed at a folder that doesn't exist would still be harmless; what matters is
        // that the hook answers nothing and probes nothing for a failure that isn't the plugin kill.
        let run = await Run("hook", "repair-macros", stdin: #"{"hook_event_name":"PostToolUseFailure","error":"error: cannot find 'foo' in scope"}"#)
        #expect(run.status == 0)
        #expect(run.output.isEmpty)
    }
}
