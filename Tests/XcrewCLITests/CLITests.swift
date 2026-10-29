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

    @Test func unknownOptionIsAUsageError() async {
        // A typo such as --problem would otherwise run the full doctor.
        let run = await Run("doctor", "--problem")
        #expect(run.status == 64)
        #expect(run.output.isEmpty)
        #expect(run.errors == ["unknown option '--problem' (xcrew doctor --help)"])
    }

    @Test func aShortOptionIsRefusedToo() async {
        let run = await Run("doctor", "-l")
        #expect(run.status == 64)
        #expect(run.errors == ["unknown option '-l' (xcrew doctor --help)"])
    }

    @Test func aWordACommandDoesntTakeIsRefused() async {
        // Without the dashes, doctor would otherwise run every check.
        let run = await Run("doctor", "problems")
        #expect(run.status == 64)
        #expect(run.errors == ["unexpected 'problems' (xcrew doctor --help)"])
    }

    @Test func helpAsAnOptionsValueIsTheValue() async {
        let run = await Run("doctor", "--check", "-h")
        #expect(run.status == 64)
        #expect(run.errors == ["unknown check '-h' (doctor --list)"])
    }

    @Test(arguments: ["--help", "-h"])
    func helpAfterACommandPrintsItsUsage(flag: String) async {
        let run = await Run("doctor", "--list", flag)
        #expect(run.status == 0)
        #expect(run.output.first == "usage:")
        #expect(run.output.contains("  doctor --list         list the check ids"))
        #expect(!run.output.contains { $0.contains("mobilebuildmcp/version") })
    }
}

@Suite struct SetupCommandTests {
    let simulators = FakeRunner(responses: [
        "xcrun simctl list devices available --json": .init(status: 0, stdout: #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone 18","udid":"U18","isAvailable":true}]}}"#),
    ])

    func config(_ project: Project) -> String {
        (try? String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8)) ?? ""
    }

    @Test func detectsTheWorkspaceAndTheNewestIPhone() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        let run = await Run("setup", "--app-scheme", "App", context: .fake(simulators, project: project))
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
        let run = await Run("setup", "--test-simulator", "iPhone 17", "--test-scheme", "App", context: .fake(simulators, project: project, environment: ["MCS_RESOLVED_TEST_SIMULATOR": "iPhone 9"]))
        #expect(run.status == 0)
        #expect(config(project).contains("'iPhone 17'"))
    }

    @Test func findsTheContainerAFolderOrTwoDown() async {
        let project = Project.temporary(containing: [".git", "apps/ios/App.xcodeproj"])
        let run = await Run("setup", "--app-scheme", "App", context: .fake(simulators, project: project))
        #expect(run.status == 0)
        #expect(config(project).contains("projectPath: '\(project.root.path)/apps/ios/App.xcodeproj'"))
    }

    @Test func aContainerAtTheRootWinsOverOneBelow() async {
        let project = Project.temporary(containing: [".git", "Root.xcodeproj", "apps/ios/App.xcworkspace"])
        let run = await Run("setup", "--app-scheme", "App", context: .fake(simulators, project: project))
        #expect(run.status == 0)
        #expect(config(project).contains("projectPath: '\(project.root.path)/Root.xcodeproj'"))
    }

    @Test func severalContainersBelowTheRootAreAQuestion() async {
        let project = Project.temporary(containing: [".git", "apps/ios/App.xcodeproj", "apps/macos/Mac.xcodeproj"])
        let run = await Run("setup", context: .fake(simulators, project: project))
        #expect(run.status == 64)
        #expect(run.errors == ["several projects a folder or two down (apps/ios/App.xcodeproj, apps/macos/Mac.xcodeproj): pass --container"])
    }

    @Test func aGeneratedProjectWithoutItsWorkspaceIsGeneratedFirst() async {
        // A module's own project isn't the one to build; Tuist writes the workspace beside its manifests.
        let project = Project.temporary(containing: [".git", "Tuist.swift", "Projects/Feature/Feature.xcodeproj"])
        let run = await Run("setup", context: .fake(simulators, project: project))
        #expect(run.status == 64)
        #expect(run.errors.first?.contains("generate it first") == true)
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

    /// A one-app project, each scheme testing the targets named.
    func appProject(schemes: [String: [String]], targets: [String: String]) -> Project {
        let project = Project.temporary()
        project.writePBXProj(targets)
        for (name, testables) in schemes { project.writeScheme(name, testing: testables) }
        return project
    }

    @Test func theSchemeThatRunsUnitTestsBecomesTheUnitProfile() async {
        let project = appProject(schemes: ["App": ["AppTests"]], targets: ["App": "application", "AppTests": "bundle.unit-test"])
        let run = await Run("setup", "--app-scheme", "App", context: .fake(simulators, project: project))
        #expect(run.status == 0)
        #expect(config(project).contains("  unit:\n    projectPath: '\(project.root.path)/App.xcodeproj'\n    scheme: 'App'"))
        #expect(run.text.contains("xcrew: unit tests run with the App scheme (--test-scheme <name> picks another)"))
        #expect(config(project).hasSuffix("activeSessionDefaultsProfile: unit\n"))
    }

    @Test func withoutUnitTestsTheAppProfileIsActive() async {
        let project = appProject(schemes: ["App": []], targets: ["App": "application"])
        let run = await Run("setup", "--app-scheme", "App", context: .fake(simulators, project: project))
        #expect(!config(project).contains("  unit:"))
        #expect(config(project).hasSuffix("activeSessionDefaultsProfile: app\n"))
        #expect(run.status == 0)
    }

    @Test func severalTestSchemesAreListedForThePersonToChoose() async {
        let project = appProject(schemes: ["Core": ["CoreTests"], "Kit": ["KitTests"]], targets: ["CoreTests": "bundle.unit-test", "KitTests": "bundle.unit-test"])
        let run = await Run("setup", "--app-scheme", "App", context: .fake(simulators, project: project))
        #expect(run.text.contains("xcrew: several schemes run unit tests (Core, Kit): pass --test-scheme <name> to add the unit profile"))
        #expect(!config(project).contains("  unit:"))
    }

    @Test func aTestSchemeThatCantBeToldIsListedNotGuessed() async {
        let project = appProject(schemes: ["App": ["Gone"]], targets: [:])
        let run = await Run("setup", "--app-scheme", "App", context: .fake(simulators, project: project))
        #expect(run.text.contains("xcrew: couldn't tell whether these schemes run unit tests (App): pass --test-scheme <name> to add the unit profile"))
    }

    @Test func anExplicitTestSchemeWins() async {
        let project = appProject(schemes: ["Core": ["CoreTests"], "Kit": ["KitTests"]], targets: ["CoreTests": "bundle.unit-test", "KitTests": "bundle.unit-test"])
        _ = await Run("setup", "--app-scheme", "App", "--test-scheme", "Kit", context: .fake(simulators, project: project))
        #expect(config(project).contains("    scheme: 'Kit'\n    simulatorName: 'iPhone 18'"))
    }

    @Test func everyProfileGetsItsSimulatorID() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        _ = await Run("setup", "--app-scheme", "App", context: .fake(simulators, project: project))
        #expect(config(project).contains("    simulatorName: 'iPhone 18'\n    simulatorId: 'U18'"))
    }

    @Test func handWrittenConfigNeedsForce() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        project.write("mine: true\n", to: ".mobilebuildmcp/config.yaml")
        #expect(await Run("setup", context: .fake(simulators, project: project)).text.contains("left as is"))
        #expect(config(project) == "mine: true\n")
        #expect(await Run("setup", "--force", "--app-scheme", "App", context: .fake(simulators, project: project)).text.contains("kept the old config"))
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

    @Test func theProjectChecksFindAnAppBelowARootOutsideGit() async {
        // Setup can configure it, so the doctor says to.
        let run = await Run("doctor", context: .fake(project: .temporary(containing: ["ios/App.xcworkspace"])))
        #expect(run.output.contains { $0.hasPrefix("FAIL  mobilebuildmcp/project-config") })
    }

    @Test func theProjectChecksSkipOutsideAnApplePlatformProject() async {
        // Following "run /xcrew:setup" there would write a MobileBuildMCP config into a project with nothing to build.
        let run = await Run("doctor")
        #expect(run.output.contains("skip  mobilebuildmcp/project-config    not an Apple project"))
        #expect(run.output.contains("skip  mobilebuildmcp/simulators        not an Apple project"))
        let inside = await Run("doctor", context: .fake(project: .temporary(containing: ["App.xcodeproj"])))
        #expect(inside.output.contains { $0.hasPrefix("FAIL  mobilebuildmcp/project-config") })
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

    @Test func problemsListedForAnAppInASubfolder() async {
        let project = Project.temporary(containing: [".git", "apps/ios/App.xcodeproj"])
        let run = await Run("doctor", "--problems", context: .fake(project: project))
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

    @Test func sessionStartNamesTheSimulatorsBootedNow() async throws {
        let plugin = Project.temporary()
        plugin.write("## Routing\n", to: "context/routing.md")
        let app = Project.temporary(containing: ["App.xcworkspace"])
        let runner = FakeRunner(responses: ["pgrep -x com.apple.CoreSimulator.CoreSimulatorService": .init(status: 0, stdout: "2216\n"), "xcrun simctl list devices booted --json": .init(status: 0, stdout: #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-2":[{"udid":"A1","state":"Booted","name":"iPhone 17","isAvailable":true}]}}"#)])
        let context = CheckContext.fake(runner, project: app, environment: ["CLAUDE_PLUGIN_ROOT": plugin.root.path])
        let run = await Run("hook", "session-start", context: context, stdin: #"{"hook_event_name":"SessionStart","cwd":"\#(app.root.path)"}"#)
        let reply = try JSONSerialization.jsonObject(with: Data(run.text.utf8)) as? [String: [String: String]]
        #expect(reply?["hookSpecificOutput"]?["additionalContext"]?.contains("Simulators booted now: iPhone 17 (iOS 27.2, A1).") == true)
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
        #expect(run.status == 0)
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

    /// Two sessions in one checkout share MobileBuildMCP's workspace; each follows the log its own server writes.
    @Test func aSessionFollowsItsOwnServersLog() async throws {
        let home = Project.temporary()
        let server = "/opt/homebrew/Cellar/mobilebuildmcp/2.7.1/libexec/node-runtime /opt/homebrew/Cellar/mobilebuildmcp/2.7.1/libexec/build/cli.js mcp"
        let ps = "  100 1 01:00:00 claude\n  200 100 05:00 \(server)\n  300 100 00:01 xcrew phase\n  400 1 01:00:00 claude\n  500 400 05:00 \(server)\n"
        let runner = FakeRunner(responses: [
            "ps -axo pid=,ppid=,etime=,command=": .init(status: 0, stdout: ps),
            "ps -axo pid=,comm=": .init(status: 0, stdout: "100 claude\n200 node-runtime\n300 xcrew\n400 claude\n500 node-runtime\n"),
        ])
        // `/work/one/App`'s workspace, as MobileBuildMCP names it (`shasum -a 256` of the path).
        home.write("SwiftCompile normal arm64 /w/A.swift (in target 'Mine' from project 'App')\n", to: "Library/Developer/MobileBuildMCP/workspaces/App-720d05200789/logs/test_sim_1_pid200_a.log")
        home.write("SwiftCompile normal arm64 /w/B.swift (in target 'Theirs' from project 'App')\n", to: "Library/Developer/MobileBuildMCP/workspaces/App-720d05200789/logs/test_sim_2_pid500_b.log")
        let logs = home.root.appending(path: "Library/Developer/MobileBuildMCP/workspaces/App-720d05200789/logs")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -5)], ofItemAtPath: logs.appending(path: "test_sim_1_pid200_a.log").path)
        let context = CheckContext(project: Project(root: URL(fileURLWithPath: "/work/one/App")), machine: Machine(environment: [:], home: home.root, runner: runner, processID: 300))
        let run = await Run("phase", "--tool", "test_sim", "--since", "0", context: context)
        #expect(run.text.contains(#""phase":"compiling Mine""#))
    }
}

@Suite struct ProjectCommandTests {
    @Test func aTuistProjectInASubfolderIsGenerated() async {
        let project = Project.temporary(containing: ["ios/Tuist.swift"])
        #expect(await Run("project", context: .fake(project: project)).text == #"{"isGenerated":true}"#)
    }

    @Test func aTuistProjectWithoutItsWorkspaceSaysToGenerateIt() async {
        let project = Project.temporary(containing: [".git", "Tuist.swift", "Projects/Feature/Feature.xcodeproj"])
        #expect(await Run("project", "--setup", context: .fake(project: project)).text == #"{"containerProblem":"no workspace beside the manifests in the project root yet: generate it first, or pass --container","isGenerated":true}"#)
    }

    @Test func aClassicProjectNamesItsContainer() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        #expect(await Run("project", context: .fake(project: project)).text == #"{"isGenerated":false}"#)
        #expect(await Run("project", "--setup", context: .fake(project: project)).text == #"{"container":"App.xcodeproj","isGenerated":false}"#)
    }

    /// Setup builds the container mcs resolved, so the answer the skill reads names the same one.
    @Test func anMCSAnswerIsTheContainerSetupWillBuild() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        let text = await Run("project", "--setup", context: .fake(project: project, environment: ["MCS_RESOLVED_PROJECT": "Other.xcworkspace"])).text
        #expect(text == #"{"container":"Other.xcworkspace","isGenerated":false}"#)
    }

    /// A module's manifest sits deeper than detection walks: it counts by its import, under the folder Tuist's manifests are in.
    @Test func anEditedManifestNamesTheCommandThatRegenerates() async {
        let project = Project.temporary(containing: ["Tuist.swift"])
        project.write("import ProjectDescription\n\nlet project = Project(name: \"Feature\")\n", to: "Projects/Features/Feature/Project.swift")
        project.write("import ProjectDescription\n", to: "Tuist/ProjectDescriptionHelpers/Targets.swift")
        for manifest in ["Projects/Features/Feature/Project.swift", "Tuist/ProjectDescriptionHelpers/Targets.swift", "Tuist.swift"] {
            let text = await Run("project", "--manifest", project.root.appending(path: manifest).path, context: .fake(project: project)).text
            #expect(text == #"{"app":"","generate":"tuist generate --no-open","isGenerated":true}"#, "\(manifest)")
        }
    }

    @Test func aSourceFileNamedLikeAManifestRegeneratesNothing() async {
        let project = Project.temporary(containing: ["Tuist.swift"])
        project.write("struct Project {}\n", to: "Projects/Feature/Sources/Project.swift")
        project.write("struct Model {}\n", to: "Projects/Feature/Sources/Model.swift")
        for file in ["Projects/Feature/Sources/Project.swift", "Projects/Feature/Sources/Model.swift"] {
            let text = await Run("project", "--manifest", project.root.appending(path: file).path, context: .fake(project: project)).text
            #expect(text == #"{"isGenerated":true}"#, "\(file)")
        }
    }

    /// The mod passes the path the edit tool was given, which may be relative to where Claude works: the project's root.
    @Test func aManifestMayBeNamedFromTheRoot() async {
        let project = Project.temporary(containing: ["ios/project.yml"])
        let text = await Run("project", "--manifest", "ios/project.yml", context: .fake(project: project)).text
        #expect(text == #"{"app":"ios","generate":"xcodegen generate --spec ios/project.yml","isGenerated":true}"#)
    }

    /// A module's manifest within reach of the walk still belongs to the app whose `Tuist.swift` is above it: generating the
    /// module alone would leave the workspace Claude builds as it was.
    @Test func aModulesManifestRegeneratesItsApp() async {
        let project = Project.temporary(containing: ["Tuist.swift"])
        project.write("import ProjectDescription\n", to: "Modules/Feature/Project.swift")
        let text = await Run("project", "--manifest", project.root.appending(path: "Modules/Feature/Project.swift").path, context: .fake(project: project)).text
        #expect(text == #"{"app":"","generate":"tuist generate --no-open","isGenerated":true}"#)
    }

    /// Tuist resolves the dependencies `Tuist/Package.swift` declares only on `tuist install`; a generate alone keeps the old ones.
    @Test func aDependencyEditInstallsBeforeGenerating() async {
        let project = Project.temporary(containing: ["ios/Tuist"])
        project.write("// swift-tools-version: 6.0\n", to: "ios/Tuist/Package.swift")
        let text = await Run("project", "--manifest", project.root.appending(path: "ios/Tuist/Package.swift").path, context: .fake(project: project)).text
        #expect(text == #"{"app":"ios","generate":"tuist install --path ios && tuist generate --no-open --path ios","isGenerated":true}"#)
    }

    /// A repository may keep more than one Tuist app: an edit regenerates the one whose manifests it changed.
    @Test func anEditInASecondTuistAppRegeneratesThatApp() async {
        let project = Project.temporary(containing: ["apps/a/Tuist.swift", "apps/b/Tuist.swift"])
        project.write("import ProjectDescription\n", to: "apps/b/Project.swift")
        let text = await Run("project", "--manifest", project.root.appending(path: "apps/b/Project.swift").path, context: .fake(project: project)).text
        #expect(text == #"{"app":"apps/b","generate":"tuist generate --no-open --path apps/b","isGenerated":true}"#)
    }

    /// XcodeGen reads every spec its spec includes, at any depth, resolved as its loader does: a top-level include from the
    /// root spec's folder, a nested one from the folder of the spec that includes it, or with `relativePaths: false` from
    /// that spec's own base (docs/findings.md, *XcodeGen's included specs*).
    @Test func aSpecTheSpecIncludesRegeneratesTheProject() async {
        let project = Project.temporary(containing: ["ios"])
        project.write("name: App\ninclude:\n  - targets/App.yml\n  - ../shared.yml\n", to: "ios/project.yml")
        project.write("settings: {}\n", to: "shared.yml")
        project.write("include:\n  - shared/base.yml\n  - path: common.yml\n    relativePaths: false\n", to: "ios/targets/App.yml")
        project.write("settings: {}\n", to: "ios/targets/shared/base.yml")
        project.write("settings: {}\n", to: "ios/common.yml")
        for spec in ["ios/targets/App.yml", "ios/targets/shared/base.yml", "ios/common.yml", "shared.yml"] {
            let text = await Run("project", "--manifest", project.root.appending(path: spec).path, context: .fake(project: project)).text
            #expect(text == #"{"app":"ios","generate":"xcodegen generate --spec ios/project.yml","isGenerated":true}"#, "\(spec)")
        }
    }

    /// An absolute include is read where it says, and its own includes resolve from there, as XcodeGen's path joining does.
    @Test func anAbsoluteIncludeIsReadWhereItSays() async {
        let project = Project.temporary(containing: [])
        let shared = Project.temporary(containing: [])
        project.write("include: \(shared.root.appending(path: "specs/base.yml").path)\n", to: "project.yml")
        shared.write("include: inner.yml\n", to: "specs/base.yml")
        shared.write("settings: {}\n", to: "specs/inner.yml")
        for spec in ["specs/base.yml", "specs/inner.yml"] {
            let text = await Run("project", "--manifest", shared.root.appending(path: spec).path, context: .fake(project: project)).text
            #expect(text == #"{"app":"","generate":"xcodegen generate","isGenerated":true}"#, "\(spec)")
        }
    }

    /// XcodeGen reads includes depth first, in the order written, and reads each spec once: the first route to a spec
    /// decides where its own includes resolve.
    @Test func aSpecReachedTwiceResolvesFromItsFirstRoute() async {
        let project = Project.temporary(containing: [])
        project.write("include:\n  - x/common.yml\n  - path: y/next.yml\n", to: "project.yml")
        project.write("include: inner.yml\n", to: "x/common.yml")
        project.write("include:\n  - path: x/common.yml\n    relativePaths: false\n", to: "y/next.yml")
        project.write("settings: {}\n", to: "x/inner.yml")
        let text = await Run("project", "--manifest", project.root.appending(path: "x/inner.yml").path, context: .fake(project: project)).text
        #expect(text == #"{"app":"","generate":"xcodegen generate","isGenerated":true}"#)
    }

    @Test func aYAMLFileNoSpecIncludesRegeneratesNothing() async {
        let project = Project.temporary(containing: [])
        project.write("name: App\ninclude: [a.yml, b.yml]\n", to: "project.yml")
        project.write("include: project.yml\n", to: "a.yml")
        project.write("on: push\n", to: ".github/workflows/ci.yml")
        project.write("include: a.yml\n", to: "Unrelated/other.yml")
        for file in [".github/workflows/ci.yml", "Unrelated/other.yml"] {
            let text = await Run("project", "--manifest", project.root.appending(path: file).path, context: .fake(project: project)).text
            #expect(text == #"{"isGenerated":true}"#, "\(file)")
        }
        // A cycle back to the spec ends, with every spec in it counted.
        let text = await Run("project", "--manifest", project.root.appending(path: "a.yml").path, context: .fake(project: project)).text
        #expect(text == #"{"app":"","generate":"xcodegen generate","isGenerated":true}"#)
    }

    /// Claude may edit another project's manifests from this one: that changes nothing this project builds.
    @Test func aManifestOutsideTheManifestsFolderRegeneratesNothing() async {
        let project = Project.temporary(containing: ["ios/Tuist.swift"])
        let other = Project.temporary(containing: ["Tuist.swift"])
        let text = await Run("project", "--manifest", other.root.appending(path: "Tuist.swift").path, context: .fake(project: project)).text
        #expect(text == #"{"isGenerated":true}"#)
    }

    @Test func projectsEquallyNearAreAQuestion() async {
        let project = Project.temporary(containing: [".git", "apps/ios/App.xcodeproj", "apps/macos/App.xcodeproj"])
        let text = await Run("project", "--setup", context: .fake(project: project)).text
        #expect(text.contains(#""containerProblem":"several projects a folder or two down"#))
        #expect(!text.contains(#""container":"#))
    }
}
