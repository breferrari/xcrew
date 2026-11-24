import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// The scheme that launches the app, as Claude reads it beside the Xcode MCP's runs: the config's `app` profile, else
/// the project's shared schemes by setup's own rule.
@Suite struct AppSchemesTests {
    /// Xcode 27.2's JSON format, one application target per name and a framework.
    static func spec(apps: [String]) -> String {
        let targets = apps.map { #"{ "name": "\#($0)", "id": "\#($0)", "product-type": "application", "product": "Products/\#($0).app" }"# }
            + [#"{ "name": "Core", "id": "C", "product-type": "framework", "product": "Products/Core.framework" }"#]
        return #"{ "targets": [ \#(targets.joined(separator: ", ")) ] }"#
    }

    func project(apps: [String] = ["App"]) -> Project {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write(Self.spec(apps: apps), to: "App.xcodeproj/project.xcproj")
        project.writeScheme("Core", building: ["Core"])
        return project
    }

    func appSchemes(_ project: Project) -> AppSchemes {
        AppSchemes.of(project, home: project.root.appending(path: "home"))
    }

    @Test func theAppProfilesSchemeWinsOverTheProjects() {
        let project = project()
        project.writeScheme("App", building: ["App"], launching: "App")
        project.write("schemaVersion: 1\nsessionDefaultsProfiles:\n  app:\n    projectPath: \"App.xcodeproj\"\n    scheme: \"Shell\"\nactiveSessionDefaultsProfile: app\n", to: ".mobilebuildmcp/config.yaml")
        #expect(appSchemes(project).names == ["Shell"])
    }

    @Test func withoutAConfigTheOneSchemeThatBuildsAnAppIsNamed() {
        let project = project()
        project.writeScheme("App", building: ["App"], launching: "App")
        #expect(appSchemes(project).names == ["App"])
    }

    @Test func ofTwoTheOneNamedForItsAppIsNamed() {
        let project = project()
        project.writeScheme("App", building: ["App"], launching: "App")
        project.writeScheme("App-Workspace", building: ["App", "Core"])
        #expect(appSchemes(project).names == ["App"])
    }

    @Test func manyAppsAreNamedThreeAndTheRestCounted() {
        let apps = ["Echo", "Delta", "Charlie", "Bravo", "Alpha"]
        let project = project(apps: apps)
        for app in apps { project.writeScheme("\(app)Scheme", building: [app], launching: app) }
        let schemes = appSchemes(project)
        #expect(schemes.names == ["AlphaScheme", "BravoScheme", "CharlieScheme", "DeltaScheme", "EchoScheme"])
        #expect(schemes.briefingNote?.hasSuffix(" Schemes that launch an app: `AlphaScheme`, `BravoScheme`, `CharlieScheme` and 2 more.") == true)
    }

    @Test func withoutAnAppSchemeThereAreNoNotes() {
        let schemes = appSchemes(project())
        #expect(schemes.names.isEmpty)
        #expect(schemes.briefingNote == nil)
        #expect(schemes.failedLaunchNote == nil)
    }

    @Test func oneTwoOrThreeNamesAreJoinedWithAnd() {
        #expect(AppSchemes(names: ["App"], isGenerated: false).briefingNote?.hasSuffix(" `App` launches the app.") == true)
        #expect(AppSchemes(names: ["A", "B"], isGenerated: false).briefingNote?.hasSuffix(" Schemes that launch an app: `A` and `B`.") == true)
        #expect(AppSchemes(names: ["A", "B", "C"], isGenerated: false).briefingNote?.hasSuffix(" Schemes that launch an app: `A`, `B` and `C`.") == true)
    }

    @Test func theNotesSayWhatRunProjectRunsAndOfferTheSwitch() {
        let schemes = AppSchemes(names: ["App"], isGenerated: false)
        #expect(schemes.briefingNote == "The Xcode MCP's `RunProject` builds and runs Xcode's active scheme and takes no scheme of its own; `XcodeSwitchScheme` selects one and keeps the run destination. `App` launches the app.")
        #expect(schemes.failedLaunchNote == "xcrew: `RunProject` built Xcode's active scheme and launched nothing from it, which happens when that scheme has no app to launch, and also when the app fails at launch. `App` launches the app. `XcodeSwitchScheme` selects a scheme and keeps the run destination.")
    }

    @Test func aGeneratedProjectsNotesSayARegenerateResetsTheSelection() {
        let reset = " A regenerate resets Xcode's selection to the first scheme in alphabetical order."
        #expect(AppSchemes(names: ["App"], isGenerated: true).briefingNote?.hasSuffix(reset) == true)
        #expect(AppSchemes(names: ["App"], isGenerated: true).failedLaunchNote?.hasSuffix(reset) == true)
        #expect(AppSchemes(names: ["App"], isGenerated: false).briefingNote?.contains("regenerate") == false)
    }

    @Test func aTuistProjectIsGenerated() {
        let project = project()
        project.write("import ProjectDescription\n", to: "Tuist.swift")
        #expect(appSchemes(project).isGenerated)
        #expect(!appSchemes(self.project()).isGenerated)
    }
}
