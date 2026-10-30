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

    /// The scheme itself, by the same rule, for a run whose call names none: the history keeps the run under it.
    @Test func theSchemeToBuildIsNamed() {
        #expect(ConfigRenderer.schemeToBuild(in: "sessionDefaultsProfiles:\n  unit:\n    scheme: AppTests\nactiveSessionDefaultsProfile: unit\n") == "AppTests")
        #expect(ConfigRenderer.schemeToBuild(in: "sessionDefaultsProfiles:\n  unit:\n    simulatorName: iPhone 17\n  app:\n    scheme: App\nactiveSessionDefaultsProfile: unit\n") == nil)
        #expect(ConfigRenderer.schemeToBuild(in: "schemaVersion: 1\nsessionDefaults:\n  scheme: 'App Tests' # the app's\n  workspacePath: ./App.xcworkspace\n") == "App Tests")
        #expect(ConfigRenderer.schemeToBuild(in: "schemaVersion: 1\nsessionDefaults:\n  workspacePath: ./App.xcworkspace\n") == nil)
    }

    /// An empty scheme, or YAML's null, names none: there's nothing to build with.
    @Test func anEmptyOrNullSchemeIsNone() {
        #expect(ConfigRenderer.schemeToBuild(in: "sessionDefaultsProfiles:\n  unit:\n    scheme: ''\nactiveSessionDefaultsProfile: unit\n") == nil)
        #expect(ConfigRenderer.schemeToBuild(in: "schemaVersion: 1\nsessionDefaults:\n  scheme: null\n") == nil)
        #expect(ConfigRenderer.schemeToBuild(in: "schemaVersion: 1\nsessionDefaults:\n  scheme: ~\n") == nil)
    }
}
