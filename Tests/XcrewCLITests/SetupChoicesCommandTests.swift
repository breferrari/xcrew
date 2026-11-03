import Foundation
import Testing
@testable import XcrewCLI
import XcrewCore
import XcrewTestSupport

/// `xcrew setup --choices`: what the setup form offers, as JSON, writing nothing.
@Suite struct SetupChoicesCommandTests {
    func choices(_ project: Project, _ argv: String...) async throws -> SetupChoices {
        let run = await Run(argv.isEmpty ? "setup" : argv[0], argv.isEmpty ? "--choices" : argv[1], context: .fake(.simulators(["iPhone 18"]), project: project))
        #expect(run.status == 0, "\(run.errors)")
        return try JSONDecoder().decode(SetupChoices.self, from: Data(run.text.utf8))
    }

    @Test func itNamesTheContainerSetupWouldBuildAndWritesNothing() async throws {
        let project = Project.temporary(containing: ["App.xcworkspace", "App.xcodeproj"])
        let choices = try await choices(project)
        #expect(choices.container == "App.xcworkspace")
        #expect(choices.containers == ["App.xcworkspace", "App.xcodeproj"])
        #expect(choices.simulators.map(\.name) == ["iPhone 18"])
        #expect(choices.picks.testSimulator == "iPhone 18")
        #expect(!project.hasMobileBuildMCPConfig)
    }

    @Test func twoFoldersEquallyNearAreAProblemWithTheirContainersAsTheChoices() async throws {
        let project = Project.temporary(containing: ["ios/App.xcodeproj", "macos/App.xcodeproj"])
        let choices = try await choices(project)
        #expect(choices.container == nil)
        #expect(choices.containerProblem?.hasPrefix("several projects a folder or two down") == true)
        #expect(Set(choices.containers) == ["ios/App.xcodeproj", "macos/App.xcodeproj"])
    }

    @Test func aContainerItNamesIsTheOneRead() async throws {
        let project = Project.temporary(containing: ["ios/App.xcodeproj", "macos/App.xcodeproj"])
        project.writeScheme("Mac", folder: "macos/App.xcodeproj/xcshareddata")
        let run = await Run("setup", "--choices", "--container", "macos/App.xcodeproj", context: .fake(.simulators(["iPhone 18"]), project: project))
        let choices = try JSONDecoder().decode(SetupChoices.self, from: Data(run.text.utf8))
        #expect(choices.container == "macos/App.xcodeproj")
        #expect(choices.containerProblem == nil)
        #expect(choices.schemes.map(\.name) == ["Mac"])
    }

    @Test func choicesTakeNoOtherOption() async {
        let run = await Run("setup", "--choices", "--force", context: .fake(.simulators(["iPhone 18"])))
        #expect(run.status == 64)
        #expect(run.errors == ["setup --choices takes no option but --container: it writes nothing"])
    }

    /// mcs's answers are what setup writes, so they're the picks too.
    @Test func mcsAnswersAreThePicks() async throws {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        let environment = ["MCS_RESOLVED_TEST_SIMULATOR": "iPhone 17", "MCS_RESOLVED_APP_SCHEME": "Mine", "MCS_RESOLVED_UI_TEST_SCHEME": "MineUI", "MCS_RESOLVED_TEST_SCHEME": "MineTests", "MCS_RESOLVED_APP_BUNDLE_ID": "dev.mine"]
        let run = await Run("setup", "--choices", context: .fake(.simulators(["iPhone 17", "iPhone 18"]), project: project, environment: environment))
        let choices = try JSONDecoder().decode(SetupChoices.self, from: Data(run.text.utf8))
        let picks = choices.picks
        #expect([picks.appScheme, picks.uiScheme, picks.testScheme, picks.bundleID, picks.testSimulator] == ["Mine", "MineUI", "MineTests", "dev.mine", "iPhone 17"])
    }

    /// The form starts from the container the config builds, as setup keeps it, not mcs's answer naming another.
    @Test func theFormStartsFromTheConfigsContainer() async throws {
        let project = Project.temporary(containing: ["App.xcworkspace", "Other.xcworkspace"])
        _ = await Run("setup", "--container", "App.xcworkspace", "--test-scheme", "AppTests", "--test-simulator", "iPhone 18", context: .fake(.simulators(["iPhone 18"]), project: project))
        let run = await Run("setup", "--choices", context: .fake(.simulators(["iPhone 18"]), project: project, environment: ["MCS_RESOLVED_PROJECT": "./Other.xcworkspace"]))
        let choices = try JSONDecoder().decode(SetupChoices.self, from: Data(run.text.utf8))
        #expect(choices.container == "App.xcworkspace")
    }

    /// The config's choices are its container's: the form for another container starts from setup's own picks.
    @Test func anotherContainersFormDoesntStartFromTheConfigsChoices() async throws {
        let project = Project.temporary(containing: ["App.xcworkspace", "Other.xcworkspace"])
        _ = await Run("setup", "--container", "App.xcworkspace", "--test-scheme", "AppTests", "--app-scheme", "App", "--bundle-id", "com.example.App", "--test-simulator", "iPhone 18", context: .fake(.simulators(["iPhone 18"]), project: project))
        let run = await Run("setup", "--choices", "--container", "Other.xcworkspace", context: .fake(.simulators(["iPhone 18"]), project: project))
        let choices = try JSONDecoder().decode(SetupChoices.self, from: Data(run.text.utf8))
        #expect([choices.picks.appScheme, choices.picks.testScheme, choices.picks.bundleID] == [nil, nil, nil])
    }

    /// A container the config names from the home folder, outside the project, is read where it is.
    @Test func aContainerOutsideTheProjectIsReadWhereItIs() async throws {
        let home = Project.temporary(containing: ["App.xcworkspace"])
        home.writeScheme("App", folder: "App.xcworkspace/xcshareddata")
        let project = Project.temporary(containing: [])
        project.write("schemaVersion: 1\nsessionDefaults:\n  workspacePath: ~/App.xcworkspace\n  simulatorName: 'iPhone 18'\n", to: ".mobilebuildmcp/config.yaml")
        let machine = Machine(environment: [:], home: home.root, runner: FakeRunner.simulators(["iPhone 18"]), processID: 1, applications: project.root.appending(path: "Applications"))
        let run = await Run("setup", "--choices", context: CheckContext(project: project, machine: machine))
        let choices = try JSONDecoder().decode(SetupChoices.self, from: Data(run.text.utf8))
        #expect(choices.schemes.map(\.name) == ["App"])
    }

    /// A config of session defaults alone holds no scheme: the form starts from setup's own scheme picks and mcs's
    /// answers, with the config's simulator.
    @Test func sessionDefaultsAloneLeaveTheSchemesToSetupAndMCS() async throws {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.writeScheme("App", folder: "App.xcodeproj/xcshareddata")
        project.write("schemaVersion: 1\nsessionDefaults:\n  projectPath: ./App.xcodeproj\n  simulatorName: 'iPhone 17'\n", to: ".mobilebuildmcp/config.yaml")
        let run = await Run("setup", "--choices", context: .fake(.simulators(["iPhone 17", "iPhone 18"]), project: project, environment: ["MCS_RESOLVED_UI_TEST_SCHEME": "MineUI"]))
        let choices = try JSONDecoder().decode(SetupChoices.self, from: Data(run.text.utf8))
        #expect(choices.picks.testSimulator == "iPhone 17")
        #expect(choices.picks.uiScheme == "MineUI")
    }

    /// Plain setup's options keep their description, and `--choices` its own.
    @Test func theUsageKeepsEachFormsDescription() async {
        let lines = await Run("setup", "--help").output
        let choices = lines.firstIndex { $0.contains("setup --choices") } ?? 0
        let description = lines.firstIndex { $0.contains("write .mobilebuildmcp/config.yaml; simulators default") } ?? 0
        #expect(description < choices, "\(lines)")
    }
}
