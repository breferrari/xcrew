import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// The scheme that launches the app, as Claude reads it beside the Xcode MCP's runs: the config's `app` profile's, and
/// none without one.
@Suite struct AppSchemeTests {
    /// A project whose config's `app` profile names `appProfile`, beside a `unit` profile; no `app` profile with nil.
    func project(appProfile: String? = "App") -> Project {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write(ConfigRenderer.render(.init(container: "App.xcodeproj", testSimulator: "iPhone 17", appScheme: appProfile, testScheme: "Core"), root: project.root), to: ".mobilebuildmcp/config.yaml")
        return project
    }

    @Test func theAppProfilesSchemeIsNamed() {
        #expect(AppScheme.of(project(appProfile: "Shell"))?.name == "Shell")
    }

    /// The project's own schemes aren't read: only the `app` profile names one.
    @Test func withoutAnAppProfileNoSchemeIsNamed() {
        let project = project(appProfile: nil)
        project.writePBXProj(["App": "application"])
        project.writeScheme("App", building: ["App"], launching: "App")
        #expect(AppScheme.of(project) == nil)
        try? FileManager.default.removeItem(at: project.mobileBuildMCPConfig)
        #expect(AppScheme.of(project) == nil)
    }

    @Test func theNotesSayWhatRunProjectRunsAndOfferTheSwitch() {
        let scheme = AppScheme(name: "App", isGenerated: false)
        #expect(scheme.briefingNote == "The Xcode MCP's `RunProject` builds and runs Xcode's active scheme and takes no scheme of its own; `XcodeSwitchScheme` selects one and keeps the run destination. `App` launches the app.")
        #expect(scheme.failedLaunchNote == "xcrew: `RunProject` built Xcode's active scheme and launched nothing from it, which happens when that scheme has no app to launch, and also when the app fails at launch. `App` launches the app. `XcodeSwitchScheme` selects a scheme and keeps the run destination.")
    }

    @Test func aGeneratedProjectsNotesSayARegenerateResetsTheSelection() {
        let reset = " A regenerate resets Xcode's selection to the first scheme in alphabetical order."
        #expect(AppScheme(name: "App", isGenerated: true).briefingNote.hasSuffix(reset))
        #expect(AppScheme(name: "App", isGenerated: true).failedLaunchNote.hasSuffix(reset))
    }
}
