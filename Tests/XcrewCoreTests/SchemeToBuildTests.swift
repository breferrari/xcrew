import Foundation
import Testing

@testable import XcrewCore

/// Whether MobileBuildMCP has a scheme to build with, as its source reads the config (docs/findings.md, *MobileBuildMCP's
/// profiles*): the active profile alone, or the global defaults when no profile is active.
@Suite struct SchemeToBuildTests {
    @Test func theActiveProfilesSchemeBuilds() {
        #expect(ConfigRenderer.hasSchemeToBuild(in: "sessionDefaultsProfiles:\n  unit:\n    scheme: AppTests\nactiveSessionDefaultsProfile: unit\n"))
    }

    /// A named profile stands alone, so another profile's scheme doesn't help the active one.
    @Test func anActiveProfileWithoutASchemeDoesntBuildWhateverTheOthersName() {
        #expect(!ConfigRenderer.hasSchemeToBuild(in: "sessionDefaultsProfiles:\n  unit:\n    simulatorName: iPhone 17\n  app:\n    scheme: App\nactiveSessionDefaultsProfile: unit\n"))
    }

    /// What MobileBuildMCP writes itself when Claude saves session defaults with a scheme.
    @Test func withNoActiveProfileTheGlobalSchemeBuilds() {
        #expect(ConfigRenderer.hasSchemeToBuild(in: "schemaVersion: 1\nsessionDefaults:\n  scheme: App\n  workspacePath: ./App.xcworkspace\n"))
    }

    @Test func globalDefaultsWithoutASchemeDontBuild() {
        #expect(!ConfigRenderer.hasSchemeToBuild(in: "schemaVersion: 1\nsessionDefaults:\n  workspacePath: ./App.xcworkspace\nenabledWorkflows:\n  - simulator\n"))
    }
}
