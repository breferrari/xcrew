import Foundation
import Testing
@testable import XcrewCLI
import XcrewCore
import XcrewTestSupport

/// What `project` answers the mod about the scheme MobileBuildMCP builds with: a named profile's, and Xcode's selection
/// when Xcode hosts the server (docs/findings.md, *Xcode's scheme selection*).
@Suite struct ProjectXcodeTests {
    static let profiles = "sessionDefaultsProfiles:\n  unit:\n    workspacePath: ./App.xcworkspace\n    scheme: AppTests\n  app:\n    workspacePath: ./App.xcworkspace\n    scheme: App\nactiveSessionDefaultsProfile: unit\n"

    /// A profile chosen during the session, before any answer listed the profiles.
    @Test func aNamedProfilesSchemeIsAnswered() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        project.write(Self.profiles, to: ".mobilebuildmcp/config.yaml")
        #expect(await Run("project", "--profiles", "--profile", "app", context: .fake(project: project)).text == #"{"isGenerated":false,"scheme":"App"}"#)
        #expect(await Run("project", "--profiles", "--profile", "gone", context: .fake(project: project)).text == #"{"isGenerated":false}"#)
    }

    @Test func underXcodeItsSelectionIsAnswered() async throws {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        project.write(Self.profiles, to: ".mobilebuildmcp/config.yaml")
        try FakeXcodeState.write(scheme: "Feature", for: "App.xcworkspace", in: project)
        let context = CheckContext.fake(.mobileBuildMCP(serving: project, underXcode: true), project: project, processID: 40)
        let state = project.root.appending(path: FakeXcodeState.path(of: "App.xcworkspace")).standardizedFileURL.path
        let answer = try JSONDecoder().decode(ProjectCommand.Answer.self, from: Data(await Run("project", "--xcode", context: context).text.utf8))
        #expect(answer.activeProfile == "unit")
        #expect(answer.xcodeScheme == "Feature")
        #expect(answer.xcodeState == state)
        #expect(answer.followsXcode == true)
        #expect(answer.xcodeHostsServer == true)
        #expect(await Run("project", "--xcuserstate", state, context: .fake(project: project)).text == #"{"isGenerated":false,"xcodeScheme":"Feature"}"#)
    }

    @Test func outsideXcodeNoSelectionIsAnswered() async throws {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        project.write(Self.profiles, to: ".mobilebuildmcp/config.yaml")
        try FakeXcodeState.write(scheme: "Feature", for: "App.xcworkspace", in: project)
        let context = CheckContext.fake(.mobileBuildMCP(serving: project, underXcode: false), project: project, processID: 40)
        #expect(await Run("project", "--xcode", context: context).text == #"{"isGenerated":false,"xcodeHostsServer":false}"#)
        // No server yet, as before Claude Code starts it: nothing is said, so the mod asks again.
        #expect(await Run("project", "--xcode", context: .fake(project: project, processID: 40)).text == #"{"isGenerated":false}"#)
        #expect(await Run("project", "--xcuserstate", "/nonexistent/UserInterfaceState.xcuserstate", context: context).text == #"{"isGenerated":false}"#)
    }
}

