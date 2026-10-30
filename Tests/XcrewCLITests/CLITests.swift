import Foundation
import Testing
@testable import XcrewCLI
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
        #expect(config(project).contains("workspacePath: './App.xcworkspace'"))
        #expect(config(project).contains("simulatorName: 'iPhone 18'"))
    }

    /// MobileBuildMCP's DAP backend runs no LLDB commands such as `expr`; setup writes the CLI backend when asked, and keeps
    /// one the config has when it writes again, `--force` included (docs/findings.md, *MobileBuildMCP errors with a way
    /// around them*).
    @Test func theDebuggerBackendIsWrittenWhenAskedAndKeptAfter() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        _ = await Run("setup", "--app-scheme", "App", "--debugger-backend", "lldb-cli", context: .fake(simulators, project: project))
        #expect(config(project).contains("\ndebuggerBackend: lldb-cli\n"))
        _ = await Run("setup", "--force", "--app-scheme", "App", "--test-simulator", "iPhone 18", context: .fake(simulators, project: project))
        #expect(config(project).contains("\ndebuggerBackend: lldb-cli\n"))
    }

    /// MobileBuildMCP resolves the config's paths against its working directory, the project root, so a config copied
    /// into another worktree builds that worktree's checkout (docs/findings.md, *MobileBuildMCP's config paths*).
    @Test func pathsAreWrittenFromTheProjectRoot() async {
        let project = Project.temporary(containing: ["ios/App.xcodeproj"])
        project.write("schemaVersion: 1\nsessionDefaults:\n  derivedDataPath: \(project.root.path)/.mobilebuildmcp/DerivedData\n", to: ".mobilebuildmcp/config.yaml")
        let run = await Run("setup", "--force", "--container", "\(project.root.path)/ios/App.xcodeproj", "--test-scheme", "AppTests", context: .fake(simulators, project: project))
        #expect(run.status == 0)
        #expect(config(project).contains("    projectPath: './ios/App.xcodeproj'\n"))
        #expect(config(project).contains("    derivedDataPath: ./.mobilebuildmcp/DerivedData\n"))
        #expect(!config(project).contains(project.root.path))
    }

    /// A profile stands alone in MobileBuildMCP, so the old config's session defaults that setup doesn't set itself go
    /// into each profile rather than being dropped.
    static let ownConfig = "schemaVersion: 1\nsessionDefaults:\n  workspacePath: ./App.xcworkspace\n  derivedDataPath: ./.mobilebuildmcp/DerivedData\n  suppressWarnings: false\n  platform: iOS\n  env:\n    APP_MODE: test\n"

    @Test func theOldSessionDefaultsSetupDoesntSetGoIntoEachProfile() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        project.write(Self.ownConfig, to: ".mobilebuildmcp/config.yaml")
        let run = await Run("setup", "--force", "--test-scheme", "AppTests", "--app-scheme", "App", "--test-simulator", "iPhone 18", context: .fake(simulators, project: project))
        #expect(run.status == 0)
        let carried = "    derivedDataPath: ./.mobilebuildmcp/DerivedData\n    suppressWarnings: false\n    platform: iOS\n    env:\n      APP_MODE: test\n"
        #expect(config(project).contains("  unit:\n    workspacePath: './App.xcworkspace'\n    scheme: 'AppTests'\n    simulatorName: 'iPhone 18'\n    simulatorId: 'U18'\n" + carried))
        #expect(config(project).contains("  app:\n    workspacePath: './App.xcworkspace'\n    scheme: 'App'\n    simulatorName: 'iPhone 18'\n    simulatorId: 'U18'\n" + carried))
        #expect(!config(project).contains("sessionDefaults:\n"))
        #expect(run.text.contains("xcrew: carried derivedDataPath, env, platform, suppressWarnings from the old config into each profile"))
    }

    /// Setup run again over its own config keeps what it carried, in each profile.
    @Test func whatSetupCarriedStaysWhenItRunsAgain() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        project.write(Self.ownConfig, to: ".mobilebuildmcp/config.yaml")
        _ = await Run("setup", "--force", "--test-scheme", "AppTests", "--test-simulator", "iPhone 18", context: .fake(simulators, project: project))
        let first = config(project)
        let again = await Run("setup", "--test-scheme", "AppTests", "--test-simulator", "iPhone 18", context: .fake(simulators, project: project))
        #expect(again.status == 0)
        #expect(config(project) == first)
        #expect(first.contains("    derivedDataPath: ./.mobilebuildmcp/DerivedData\n"))
    }

    /// A profile setup adds on a later run gets what an earlier one carried, though no global defaults remain.
    @Test func aProfileAddedLaterGetsWhatWasCarried() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        project.write(Self.ownConfig, to: ".mobilebuildmcp/config.yaml")
        _ = await Run("setup", "--force", "--test-scheme", "AppTests", "--test-simulator", "iPhone 18", context: .fake(simulators, project: project))
        let again = await Run("setup", "--test-scheme", "AppTests", "--app-scheme", "App", "--test-simulator", "iPhone 18", context: .fake(simulators, project: project))
        #expect(config(project).contains("  app:\n    workspacePath: './App.xcworkspace'\n    scheme: 'App'\n    simulatorName: 'iPhone 18'\n    simulatorId: 'U18'\n    derivedDataPath: ./.mobilebuildmcp/DerivedData\n"))
        #expect(!again.text.contains("xcrew: carried"))
    }

    /// Without a scheme setup writes global defaults, which keep what the old profiles held, a scheme included.
    @Test func theGlobalDefaultsKeepWhatTheOldProfilesHeld() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        project.write("schemaVersion: 1\nsessionDefaultsProfiles:\n  mine:\n    scheme: App\n    derivedDataPath: ./DD\n    workspacePath: ./App.xcworkspace\nactiveSessionDefaultsProfile: mine\n", to: ".mobilebuildmcp/config.yaml")
        let run = await Run("setup", "--force", "--test-simulator", "iPhone 18", context: .fake(simulators, project: project))
        #expect(config(project).contains("sessionDefaults:\n  workspacePath: './App.xcworkspace'\n  simulatorName: 'iPhone 18'\n  simulatorId: 'U18'\n  scheme: App\n  derivedDataPath: ./DD\n"))
        #expect(run.text.contains("xcrew: carried derivedDataPath, scheme from the old config into the session defaults"))
    }

    /// A profile of any name carries into the ones setup writes.
    @Test func aProfileOfAnotherNameCarries() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        project.write("schemaVersion: 1\nsessionDefaultsProfiles:\n  default:\n    derivedDataPath: ./DD\n", to: ".mobilebuildmcp/config.yaml")
        _ = await Run("setup", "--force", "--test-scheme", "AppTests", "--test-simulator", "iPhone 18", context: .fake(simulators, project: project))
        #expect(config(project).contains("    simulatorId: 'U18'\n    derivedDataPath: ./DD\n"))
    }

    /// YAML may write a list's items at their key's own indent, and a block scalar keeps its blank lines.
    @Test func carriedValuesKeepTheirShape() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        project.write("schemaVersion: 1\nsessionDefaults:\n  extraArgs:\n  - -foo\n  env:\n    SCRIPT: |\n      one\n\n      # two\n", to: ".mobilebuildmcp/config.yaml")
        let run = await Run("setup", "--force", "--test-scheme", "AppTests", "--test-simulator", "iPhone 18", context: .fake(simulators, project: project))
        #expect(config(project).contains("    simulatorId: 'U18'\n    extraArgs:\n    - -foo\n    env:\n      SCRIPT: |\n        one\n\n        # two\n"))
        #expect(run.text.contains("xcrew: carried env, extraArgs from the old config into each profile"))
    }

    /// When an installed runtime supports the missing simulator, setup gives the command that creates it.
    @Test func aMissingSimulatorARuntimeSupportsGetsItsCreateCommand() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        var runner = simulators
        runner.responses["xcrun simctl list runtimes --json"] = .init(status: 0, stdout: #"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","version":"27.0","platform":"iOS","isAvailable":true,"supportedDeviceTypes":[{"name":"iPhone 16","identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-16"}]}]}"#)
        let run = await Run("setup", "--test-scheme", "AppTests", "--app-scheme", "App", "--app-simulator", "iPhone 16", context: .fake(runner, project: project))
        #expect(run.text.contains("xcrew: no simulator named iPhone 16 is installed (installed iPhones: iPhone 18): create it with xcrun simctl create \"iPhone 16\" com.apple.CoreSimulator.SimDeviceType.iPhone-16 com.apple.CoreSimulator.SimRuntime.iOS-27-0, or rerun with --app-simulator and one of those"))
    }

    /// MobileBuildMCP finds a simulator's ID only for the active profile at its start, so every profile setup writes with
    /// an installed simulator carries its own.
    @Test func everyProfileWithAnInstalledSimulatorHasItsID() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        _ = await Run("setup", "--test-scheme", "AppTests", "--app-scheme", "App", "--ui-scheme", "AppUITests", "--app-simulator", "iPhone 18", context: .fake(simulators, project: project))
        let profiles = config(project).matches(of: /(?m)^  (?:unit|app|ui):\n(?:    .*\n)*/).map { String($0.0) }
        #expect(profiles.count == 3)
        for profile in profiles { #expect(profile.contains("simulatorId: 'U18'"), "\(profile)") }
    }

    /// With no simulator list at all, `simctl` failed: that isn't a missing simulator to name.
    @Test func withoutASimulatorListNoSimulatorIsSaidMissing() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        let run = await Run("setup", "--test-scheme", "AppTests", "--test-simulator", "iPhone 18", context: .fake(FakeRunner(), project: project))
        #expect(run.status == 0)
        #expect(!run.text.contains("no simulator named"))
    }

    /// A simulator that isn't installed gets no ID, and MobileBuildMCP finds one only for the active profile: setup says
    /// so, and which are installed, but writes it, since the person may add it next.
    @Test func aSimulatorThatIsntInstalledIsNamedWithTheInstalledOnes() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        let run = await Run("setup", "--test-scheme", "AppTests", "--app-scheme", "App", "--app-simulator", "iPhone 16", context: .fake(simulators, project: project))
        #expect(run.status == 0)
        #expect(config(project).contains("simulatorName: 'iPhone 16'"))
        #expect(run.text.contains("xcrew: no simulator named iPhone 16 is installed (installed iPhones: iPhone 18): add it in Xcode, or rerun with --app-simulator and one of those"))
        let test = await Run("setup", "--force", "--test-scheme", "AppTests", "--test-simulator", "iPhone 17", context: .fake(simulators, project: project))
        #expect(test.text.contains("xcrew: no simulator named iPhone 17 is installed (installed iPhones: iPhone 18): add it in Xcode, or rerun with --test-simulator and one of those"))
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
        #expect(config(project).contains("projectPath: './apps/ios/App.xcodeproj'"))
    }

    @Test func aContainerAtTheRootWinsOverOneBelow() async {
        let project = Project.temporary(containing: [".git", "Root.xcodeproj", "apps/ios/App.xcworkspace"])
        let run = await Run("setup", "--app-scheme", "App", context: .fake(simulators, project: project))
        #expect(run.status == 0)
        #expect(config(project).contains("projectPath: './Root.xcodeproj'"))
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
        #expect(config(project).contains("  unit:\n    projectPath: './App.xcodeproj'\n    scheme: 'App'"))
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
        #expect(run.output.contains("skip  mobilebuildmcp/project-config      not an Apple project"))
        #expect(run.output.contains("skip  mobilebuildmcp/simulators          not an Apple project"))
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

    /// A pinned Xcode that isn't the one building is the Mac's own choice, never the prompt line's: the full doctor lists
    /// it, and a failure says it may be the cause.
    @Test func problemsLeavesOutTheXcodePin() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        project.write("25.0\n", to: ".xcode-version")
        let problems = await Run("doctor", "--problems", context: .fake(project: project))
        #expect(!problems.output.contains { $0.hasPrefix("warn  xcode/pin") })
        #expect(problems.output.contains { $0.hasPrefix("Kept off the prompt") && $0.contains("xcode/pin") })
        let full = await Run("doctor", context: .fake(project: project))
        #expect(full.output.contains { $0.hasPrefix("warn  xcode/pin") })
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

@Suite struct CardCommandTests {
    /// The mod sends the card it built as JSON; the folder is kept as the file system spells it, as the hook reads it.
    @Test func saveKeepsTheCardTheModSends() async {
        let project = Project.temporary()
        let context = CheckContext.fake(project: project)
        let updated = Date().timeIntervalSince1970 * 1000 - 3 * 3_600_000
        let json = #"{"version":1,"folder":"\#(project.root.path)","branch":"main","updated":\#(updated),"text":"Notes:\n- a"}"#
        let run = await Run("card", "--save", context: context, stdin: json)
        #expect(run.status == 0)
        #expect(ProjectCard.text(folder: project.canonicalRoot, branch: "main", now: Date(), on: context.machine) == "Notes, as of the run 3 h ago:\n- a")
    }
}

/// The mod sends the ledger and run times it holds; the CLI answers with the block, then the images to attach.
@Suite struct EvidenceCommandTests {
    @Test func evidencePrintsTheBlockForTheLedgerTheModSends() async {
        let json = #"{"ledger":[{"test":"Suite/testA","red":{"scope":"test_sim · App","at":1793370240000,"message":"failed"},"failing":"test_sim · App","last":1793370240000}],"times":[]}"#
        let run = await Run("evidence", context: .fake(), stdin: json)
        #expect(run.status == 0)
        #expect(run.text == "## Evidence\n\nStill red:\n- `Suite/testA`: \"failed\"")
    }

    @Test func evidenceWithNothingToSaySaysSo() async {
        let run = await Run("evidence", context: .fake(), stdin: #"{"ledger":[],"times":[]}"#)
        #expect(run.status == 0)
        #expect(run.text == EvidenceCommand.nothing)
    }

    @Test func evidenceRefusesInputThatIsntTheModsJSON() async {
        #expect(await Run("evidence", context: .fake(), stdin: "not json").status != 0)
    }
}

/// `xcrew note`: the notes for an Xcode MCP tool's result that no build or test report reads.
@Suite struct NoteCommandTests {
    @Test func aClosedConnectionHasItsNote() async {
        let run = await Run("note", "--server", "xcode", "--error", stdin: "MCP error -32000: Connection closed")
        #expect(run.text == #"{"notes":["xcrew: the Xcode MCP's connection closed, as it does when the selected Xcode changes during a session; /mcp → Reconnect restarts it."]}"#)
        #expect(await Run("note", "--server", "xcode", stdin: "MCP error -32000: Connection closed").text == #"{"notes":[]}"#)
    }
}

/// The handshake starts an Xcode MCP bridge of its own: the full doctor runs it, and the one the line above the prompt
/// runs at session start and after prompts doesn't.
@Suite struct DoctorHandshakeTests {
    @Test func onlyTheFullDoctorRunsTheHandshake() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        let context = CheckContext.fake(FakeRunner(responses: FakeSession.responses(serving: nil)), project: project, processID: FakeSession.doctor)
        #expect(await Run("doctor", "--json", context: context).text.contains("xcode-mcp/handshake"))
        #expect(!(await Run("doctor", "--problems", "--json", context: context).text.contains("xcode-mcp/handshake")))
    }
}

@Suite struct ProjectCommandTests {
    /// A file's content hash, for the manifest guard to tell an edit reverted since the last generate: SHA-256, in hex,
    /// and empty for a file that isn't there.
    @Test func projectHashesAFile() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write("let project = 1\n", to: "Project.swift")
        // `printf 'let project = 1\n' | shasum -a 256`
        #expect(await Run("project", "--hash", "Project.swift", context: .fake(project: project)).text == #"{"hash":"5e1ed27607f9dcae1c94968c6098a2b4b8212d629d2ce41df57138765aba2f5b","isGenerated":true}"#)
        #expect(await Run("project", "--hash", "Missing.swift", context: .fake(project: project)).text == #"{"hash":"","isGenerated":true}"#)
        // A file that's there but can't be read isn't one that's missing: no hash, so the edit stands.
        project.write("", to: "Folder/.keep")
        #expect(await Run("project", "--hash", "Folder", context: .fake(project: project)).text == #"{"isGenerated":true}"#)
    }

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

    /// An active profile whose scheme is empty has nothing to build with: setup is offered, as with no scheme at all.
    @Test func profilesOffersSetupForAnEmptyScheme() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write("sessionDefaultsProfiles:\n  unit:\n    scheme: ''\nactiveSessionDefaultsProfile: unit\n", to: ".mobilebuildmcp/config.yaml")
        #expect(await Run("project", "--profiles", context: .fake(project: project)).text.contains(#""setup":"#))
    }

    /// The mod asks after a build whether setup can be offered, and says the briefing's own line when it can.
    @Test func profilesSaysSetupCanBeOfferedUntilASchemeCanBuild() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        #expect(await Run("project", "--profiles", context: .fake(project: project)).text == #"{"isGenerated":false,"setup":"MobileBuildMCP has no scheme to build this project with yet. `/xcrew:setup` writes its profiles once, from the project's schemes and simulators, and can be offered to the person, who can also pick them in the form `/xcrew setup` opens."}"#)
        project.write(ConfigRenderer.render(.init(container: "App.xcodeproj", testSimulator: "iPhone 17", testScheme: "AppTests"), root: project.root), to: ".mobilebuildmcp/config.yaml")
        // The scheme it builds with, for the mod's history when a call names none.
        #expect(await Run("project", "--profiles", context: .fake(project: project)).text == #"{"isGenerated":false,"scheme":"AppTests"}"#)
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

/// The key a branch's red-to-green ledger is kept under: the project's real root, and its branch, or the commit when HEAD
/// is detached.
@Suite struct ProjectBranchTests {
    func realPath(_ project: Project) async -> String {
        await SystemCommandRunner().run(["/bin/realpath", project.root.path], stdin: nil, timeout: .seconds(10)).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test func aBranchIsNamedWithTheRealRoot() async {
        let project = Project.temporary()
        let runner = FakeRunner(responses: ["git -C \(project.root.path) symbolic-ref --short -q HEAD": .init(status: 0, stdout: "feat/ledger\n")])
        let text = await Run("project", "--branch", context: .fake(runner, project: project)).text
        #expect(text == #"{"branch":"feat/ledger","isGenerated":false,"root":"\#(await realPath(project))"}"#)
    }

    @Test func aDetachedHeadIsNamedByItsCommit() async {
        let project = Project.temporary()
        let runner = FakeRunner(responses: [
            "git -C \(project.root.path) symbolic-ref --short -q HEAD": .init(status: 1),
            "git -C \(project.root.path) rev-parse HEAD": .init(status: 0, stdout: "0123456789abcdef0123456789abcdef01234567\n"),
        ])
        let text = await Run("project", "--branch", context: .fake(runner, project: project)).text
        #expect(text == #"{"commit":"0123456789abcdef0123456789abcdef01234567","isGenerated":false,"root":"\#(await realPath(project))"}"#)
    }

    @Test func outsideARepositoryOnlyTheRootIsNamed() async {
        let project = Project.temporary()
        let text = await Run("project", "--branch", context: .fake(project: project)).text
        #expect(text == #"{"isGenerated":false,"root":"\#(await realPath(project))"}"#)
    }
}

/// What a generator writes, which an edit loses on the next generate: a project or workspace with a manifest beside it,
/// and Tuist's `Derived` folder beside a project manifest.
@Suite struct GeneratedFileTests {
    func answer(_ file: String, in project: Project) async throws -> ProjectCommand.Answer {
        try JSONDecoder().decode(ProjectCommand.Answer.self, from: Data(await Run("project", "--generated", project.root.appending(path: file).path, context: .fake(project: project)).text.utf8))
    }

    @Test func aModulesProjectNamesItsOwnManifestAndTheAppsGenerate() async throws {
        let project = Project.temporary(containing: ["Tuist.swift", "Projects/Feature/Feature.xcodeproj"])
        project.write("import ProjectDescription\n", to: "Projects/Feature/Project.swift")
        project.write("// !$*UTF8*$!\n", to: "Projects/Feature/Feature.xcodeproj/project.pbxproj")
        let found = try await answer("Projects/Feature/Feature.xcodeproj/project.pbxproj", in: project)
        #expect(found.manifest == "Projects/Feature/Project.swift")
        #expect(found.generate == "tuist generate --no-open")
    }

    /// A Write that creates a file inside a generated folder is an edit the next generate loses too, however the root is
    /// spelled: `/var` here is `/private/var` on disk.
    @Test func aNewFileInAGeneratedFolderIsGenerated() async throws {
        let project = Project.temporary(containing: ["Tuist.swift", "Derived"])
        project.write("import ProjectDescription\n", to: "Project.swift")
        #expect(try await answer("Derived/InfoPlists/New-Info.plist", in: project).manifest == "Project.swift")
    }

    /// XcodeGen writes the project its spec names, and nothing else beside it: not a workspace CocoaPods wrote, nor another project.
    @Test func xcodeGenWritesOnlyTheProjectItsSpecNames() async throws {
        let project = Project.temporary(containing: ["App.xcodeproj", "App.xcworkspace", "Other.xcodeproj"])
        project.write("name: App\n", to: "project.yml")
        project.write("// !$*UTF8*$!\n", to: "App.xcodeproj/project.pbxproj")
        project.write("<Workspace/>\n", to: "App.xcworkspace/contents.xcworkspacedata")
        project.write("// !$*UTF8*$!\n", to: "Other.xcodeproj/project.pbxproj")
        #expect(try await answer("App.xcodeproj/project.pbxproj", in: project).manifest == "project.yml")
        #expect(try await answer("App.xcworkspace/contents.xcworkspacedata", in: project).manifest == nil)
        #expect(try await answer("Other.xcodeproj/project.pbxproj", in: project).manifest == nil)
    }

    /// Each XcodeGen app's project is its own spec's, not only the nearest one's.
    @Test func aSecondXcodeGenAppsProjectNamesItsOwnSpec() async throws {
        let project = Project.temporary(containing: ["apps/a/A.xcodeproj", "apps/b/B.xcodeproj"])
        project.write("name: A\n", to: "apps/a/project.yml")
        project.write("name: B\n", to: "apps/b/project.yml")
        project.write("// !$*UTF8*$!\n", to: "apps/b/B.xcodeproj/project.pbxproj")
        let found = try await answer("apps/b/B.xcodeproj/project.pbxproj", in: project)
        #expect(found.manifest == "apps/b/project.yml")
        #expect(found.generate == "xcodegen generate --spec apps/b/project.yml")
    }

    /// Beside a checked-in project, a `Project.swift` that is a source file isn't a manifest: detection's rule decides.
    @Test func aSourceFileNamedProjectSwiftBesideAProjectIsntItsManifest() async throws {
        let project = Project.temporary(containing: ["Tuist.swift", "Modules/Legacy/Legacy.xcodeproj"])
        project.write("struct Project {}\n", to: "Modules/Legacy/Project.swift")
        project.write("// !$*UTF8*$!\n", to: "Modules/Legacy/Legacy.xcodeproj/project.pbxproj")
        #expect(try await answer("Modules/Legacy/Legacy.xcodeproj/project.pbxproj", in: project).manifest == nil)
    }

    /// A checked-in project of a dependency, or a folder that only shares Tuist's folder name, isn't Tuist's to write.
    @Test func aBundleOrDerivedFolderWithNoManifestBesideItIsntGenerated() async throws {
        let project = Project.temporary(containing: ["Tuist.swift", "Vendor/Lib.xcodeproj", "Docs/Derived"])
        project.write("// !$*UTF8*$!\n", to: "Vendor/Lib.xcodeproj/project.pbxproj")
        project.write("notes\n", to: "Docs/Derived/notes.md")
        for file in ["Vendor/Lib.xcodeproj/project.pbxproj", "Docs/Derived/notes.md"] {
            #expect(try await answer(file, in: project).manifest == nil, "\(file)")
        }
    }
}

/// `xcrew affected`: the changes since the merge base with the remote's default branch, uncommitted and untracked
/// files included, and the tests they can break. The answer names the base it used.
@Suite struct AffectedCommandTests {
    func project() -> Project {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write("""
            { "files": [ { "kind": "folder", "path": "App", "target-membership": [ "App" ] }, { "kind": "folder", "path": "AppTests", "target-membership": [ "AppTests" ] } ],
              "targets": [ { "name": "App", "id": "A", "product-type": "application" }, { "name": "AppTests", "id": "T", "product-type": "bundle.unit-test", "test-host-target": "App" } ] }
            """, to: "App.xcodeproj/project.xcproj")
        return project
    }

    func git(_ project: Project, _ answers: [String: CommandResult]) -> FakeRunner {
        FakeRunner(responses: Dictionary(uniqueKeysWithValues: answers.map { ("git -C \(project.root.path) \($0.key)", $0.value) }))
    }

    func run(_ project: Project, _ runner: FakeRunner, base: String? = nil) async throws -> [String: Any] {
        let context = CheckContext.fake(runner, project: project)
        let text = if let base { await Run("affected", "--base", base, context: context).text } else { await Run("affected", context: context).text }
        return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], "\(text)")
    }

    @Test func changesSinceTheMergeBaseWithTheDefaultBranchSelectTheirTests() async throws {
        let project = project()
        let runner = git(project, [
            "rev-parse --show-toplevel": .init(status: 0, stdout: "\(project.root.path)\n"),
            "rev-parse --abbrev-ref origin/HEAD": .init(status: 0, stdout: "origin/main\n"),
            "merge-base HEAD origin/main": .init(status: 0, stdout: "0123456789abcdef0123456789abcdef01234567\n"),
            "diff --name-only --no-renames --no-relative -z 0123456789abcdef0123456789abcdef01234567": .init(status: 0, stdout: "App/ContentView.swift\u{0}"),
            "ls-files -z --others --exclude-standard --full-name": .init(status: 0, stdout: "AppTests/NewTests.swift\u{0}"),
        ])
        let answer = try await run(project, runner)
        #expect(answer["base"] as? String == "origin/main, from 0123456789ab")
        #expect(answer["changed"] as? [String] == ["App/ContentView.swift", "AppTests/NewTests.swift"])
        #expect(answer["selections"] as? [String] == ["AppTests"])
    }

    @Test func withoutARemoteTheWorkingTreeIsTheChange() async throws {
        let project = project()
        let runner = git(project, [
            "rev-parse --show-toplevel": .init(status: 0, stdout: "\(project.root.path)\n"),
            "rev-parse --abbrev-ref origin/HEAD": .init(status: 128),
            "remote": .init(status: 0),
            "diff --name-only --no-renames --no-relative -z HEAD": .init(status: 0, stdout: "App/ContentView.swift\u{0}"),
            "ls-files -z --others --exclude-standard --full-name": .init(status: 0),
        ])
        let answer = try await run(project, runner)
        #expect(answer["base"] as? String == "the working tree, since there is no remote")
        #expect(answer["selections"] as? [String] == ["AppTests"])
    }

    @Test func aBaseNamedOnTheCommandLineIsUsed() async throws {
        let project = project()
        let runner = git(project, [
            "rev-parse --show-toplevel": .init(status: 0, stdout: "\(project.root.path)\n"),
            "merge-base HEAD release/2.0": .init(status: 0, stdout: "fedcba9876543210fedcba9876543210fedcba98\n"),
            "diff --name-only --no-renames --no-relative -z fedcba9876543210fedcba9876543210fedcba98": .init(status: 0, stdout: "README.md\u{0}"),
            "ls-files -z --others --exclude-standard --full-name": .init(status: 0),
        ])
        let answer = try await run(project, runner, base: "release/2.0")
        #expect(answer["base"] as? String == "release/2.0, from fedcba987654")
        #expect(answer["selections"] == nil)
        #expect((answer["runAll"] as? String)?.contains("README.md") == true)
    }

    @Test func outsideGitEverythingRuns() async throws {
        let answer = try await run(project(), FakeRunner())
        #expect(answer["selections"] == nil)
        #expect(answer["base"] == nil)
        #expect((answer["runAll"] as? String)?.contains("git") == true)
    }
}

/// What the first reading of git missed, each a skip that wasn't safe.
@Suite struct AffectedCommandEdgeTests {
    let base = "0123456789abcdef0123456789abcdef01234567"

    func run(_ project: Project, _ answers: [String: CommandResult]) async throws -> [String: Any] {
        let runner = FakeRunner(responses: Dictionary(uniqueKeysWithValues: (answers.merging(["rev-parse --show-toplevel": .init(status: 0, stdout: "\(project.root.path)\n")]) { first, _ in first }).map { ("git -C \(project.root.path) \($0.key)", $0.value) }))
        let text = await Run("affected", context: .fake(runner, project: project)).text
        return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], "\(text)")
    }

    /// `origin/HEAD` is set only by a clone: a pushed branch without it still has a default branch on the remote.
    @Test func withoutOriginHEADTheRemotesMainIsTheBase() async throws {
        let answer = try await run(Project.temporary(), [
            "rev-parse --abbrev-ref origin/HEAD": .init(status: 128),
            "rev-parse --verify --quiet origin/main": .init(status: 0, stdout: "\(base)\n"),
            "merge-base HEAD origin/main": .init(status: 0, stdout: "\(base)\n"),
            "diff --name-only --no-renames --no-relative -z \(base)": .init(status: 0),
            "ls-files -z --others --exclude-standard --full-name": .init(status: 0),
        ])
        #expect(answer["base"] as? String == "origin/main, from 0123456789ab")
    }

    /// With a remote and no default branch found on it, the branch's own commits can't be told apart: everything runs.
    @Test func aRemoteWithNoDefaultBranchRunsEverything() async throws {
        let answer = try await run(Project.temporary(), [
            "rev-parse --abbrev-ref origin/HEAD": .init(status: 128),
            "remote": .init(status: 0, stdout: "upstream\n"),
        ])
        #expect(answer["selections"] == nil)
        #expect((answer["runAll"] as? String)?.contains("default branch") == true)
    }

    /// Names come back as git writes them, NUL-separated, so a name with any character survives.
    @Test func aNameWithAnyCharacterSurvives() async throws {
        let answer = try await run(Project.temporary(), [
            "rev-parse --abbrev-ref origin/HEAD": .init(status: 0, stdout: "origin/main\n"),
            "merge-base HEAD origin/main": .init(status: 0, stdout: "\(base)\n"),
            "diff --name-only --no-renames --no-relative -z \(base)": .init(status: 0, stdout: "App/Café.swift\u{0}Core/Old Name.swift\u{0}"),
            "ls-files -z --others --exclude-standard --full-name": .init(status: 0),
        ])
        #expect(answer["changed"] as? [String] == ["App/Café.swift", "Core/Old Name.swift"])
    }
}

/// A base git would read as one of its options isn't a base: it could compare with HEAD and drop the branch's commits.
@Suite struct AffectedBaseTests {
    @Test func aBaseThatLooksLikeAnOptionRunsEverything() async throws {
        let project = Project.temporary()
        let runner = FakeRunner(responses: [
            "git -C \(project.root.path) rev-parse --show-toplevel": .init(status: 0, stdout: "\(project.root.path)\n"),
            "git -C \(project.root.path) merge-base HEAD --independent": .init(status: 0, stdout: "0123456789abcdef0123456789abcdef01234567\n"),
        ])
        let text = await Run("affected", "--base", "--independent", context: .fake(runner, project: project)).text
        let answer = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(answer["selections"] == nil)
        #expect((answer["runAll"] as? String)?.contains("--independent") == true)
    }
}

/// `xcrew space` prints each part, or with `--json` the same as JSON; a tool that doesn't answer is said not to.
@Suite struct SpaceCommandTests {
    @Test func eachPartIsPrintedAndAToolThatDoesntAnswerIsSaidNotTo() async {
        let run = await Run("space")
        #expect(run.status == 0)
        #expect(run.text.contains("MobileBuildMCP\n  not read: `mobilebuildmcp purge --report` didn't answer"), "\(run.text)")
    }

    @Test func theJSONIsTheSameReport() async throws {
        let text = await Run("space", "--json").text
        let report = try JSONDecoder().decode(SpaceReport.self, from: Data(text.utf8))
        #expect(report.parts.first?.title == "MobileBuildMCP")
    }
}
