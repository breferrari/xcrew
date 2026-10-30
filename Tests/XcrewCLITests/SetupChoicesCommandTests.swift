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
}
