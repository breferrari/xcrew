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

    /// Plain setup's options keep their description, and `--choices` its own.
    @Test func theUsageKeepsEachFormsDescription() async {
        let lines = await Run("setup", "--help").output
        let choices = lines.firstIndex { $0.contains("setup --choices") } ?? 0
        let description = lines.firstIndex { $0.contains("write .mobilebuildmcp/config.yaml; simulators default") } ?? 0
        #expect(description < choices, "\(lines)")
    }
}
