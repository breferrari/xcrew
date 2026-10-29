import Foundation
import Testing
import XcrewCore
import XcrewTestSupport

@Suite struct CLITests {
    @Test func helpListsEveryCommand() async {
        let run = await Run("help")
        #expect(run.status == 0)
        for name in ["setup", "doctor", "xcode-skills", "hook"] {
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

    @Test func problemsLeavesOutChecksThatReachTheNetwork() async {
        // It runs at every session start; a session shouldn't call GitHub it didn't ask to.
        let project = Project.temporary(containing: ["App.xcworkspace"])
        let latest = "curl -fsSL --max-time 5 https://api.github.com/repos/breferrari/xcrew/releases/latest"
        let runner = FakeRunner(responses: [latest: .init(status: 0, stdout: #"{"tag_name":"v99.0.0"}"#)])
        let run = await Run("doctor", "--problems", context: .fake(runner, project: project))
        #expect(!run.output.contains { $0.contains("xcrew/up-to-date") })
        let full = await Run("doctor", context: .fake(runner, project: project))
        #expect(full.output.contains { $0.hasPrefix("warn  xcrew/up-to-date") })
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

    @Test func problemsAsJSONGiveEachChecksStatusIdAndMessage() async throws {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        let run = await Run("doctor", "--problems", "--json", context: .fake(project: project))
        let lines = try JSONDecoder().decode([[String: String]].self, from: Data(run.text.utf8))
        #expect(!lines.isEmpty)
        #expect(lines.allSatisfy { $0["status"] == "fail" || $0["status"] == "warn" })
        #expect(lines.contains { $0["id"] == "mobilebuildmcp/version" && $0["status"] == "fail" && $0["message"]?.isEmpty == false })
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

    @Test func unknownHookIsAUsageError() async {
        #expect(await Run("hook", "nope").status == 64)
        #expect(await Run("hook", "repair-macros").status == 64)
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

@Suite struct ReportCommandTests {
    @Test func aFailedBuildIsReportedAsJSONTheModReads() async throws {
        let text = "🔨 Build\n\nErrors (1):\n\n  ✗ cannot find 'total' in scope\n    /work/App/CheckoutView.swift:12\n\n❌ Build failed. (⏱️ 3.2s)"
        let run = await Run("report", "--server", "MobileBuildMCP", "--kind", "build", "--error", stdin: text)
        #expect(run.status == 0)
        let report = try JSONDecoder().decode(Report.self, from: Data(run.text.utf8))
        #expect(report.ok == false)
        #expect(report.detail == "CheckoutView.swift:12 cannot find 'total' in scope")
        #expect(report.durationMs == 3_200)
        #expect(report.failures.map(\.title) == ["CheckoutView.swift:12"])
    }

    @Test func itNeedsAServerAndAKind() async {
        #expect(await Run("report", "--kind", "build").status == 64)
        #expect(await Run("report", "--server", "xcode", "--kind", "deploy").status == 64)
        #expect(await Run("report", "--server", "XcodeBuildMCP", "--kind", "build").status == 64)
    }
}

@Suite struct PhaseCommandTests {
    @Test func aRunsPhaseComesFromTheLogItWasGiven() async throws {
        let project = Project.temporary()
        project.write("SwiftCompile normal arm64 /w/A.swift (in target 'Payments' from project 'App')\n", to: "test_sim_1.log")
        let log = project.root.appending(path: "test_sim_1.log").path
        let run = await Run("phase", "--tool", "test_sim", "--since", "0", "--log", log)
        #expect(run.text == #"{"log":"\#(log)","phase":"compiling Payments"}"#)
    }

    @Test func beforeTheLogAppearsThereIsNeitherLogNorPhase() async {
        #expect(await Run("phase", "--tool", "test_sim", "--since", "0").text == "{}")
    }
}

@Suite struct ProjectCommandTests {
    @Test func aTuistProjectInASubfolderIsGenerated() async {
        let project = Project.temporary(containing: ["ios/Tuist.swift"])
        #expect(await Run("project", context: .fake(project: project)).text == #"{"isGenerated":true}"#)
    }

    @Test func aClassicProjectIsNot() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        #expect(await Run("project", context: .fake(project: project)).text == #"{"isGenerated":false}"#)
    }
}
