import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// What the setup form offers: each shared scheme with what it builds and tests, setup's own picks, installed simulators
/// only, and whose the config is.
@Suite struct SetupChoicesTests {
    /// Xcode 27.2's JSON format: an app with a literal bundle ID, its unit and UI tests, and a framework with its tests.
    static let spec = """
        {
          "targets": [
            { "name": "App", "id": "A", "product-type": "application", "product": "Products/App.app", "build-settings": { "PRODUCT_BUNDLE_IDENTIFIER": "dev.example.App" } },
            { "name": "AppTests", "id": "AT", "product-type": "bundle.unit-test", "test-host-target": "App" },
            { "name": "AppUITests", "id": "AU", "product-type": "bundle.ui-testing", "test-host-target": "App" },
            { "name": "Core", "id": "C", "product-type": "framework", "product": "Products/Core.framework" },
            { "name": "CoreTests", "id": "CT", "product-type": "bundle.unit-test", "dependencies": [ "Core" ] },
          ],
        }
        """

    func project(spec: String = spec) -> Project {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write(spec, to: "App.xcodeproj/project.xcproj")
        project.writeScheme("App", building: ["App"], testing: ["AppTests", "AppUITests"])
        project.writeScheme("Core", testing: ["CoreTests"])
        return project
    }

    static let catalog: SimulatorCatalog = {
        var catalog = SimulatorCatalog(devices: [
            .init(name: "iPhone 17", runtimeVersion: "26.5", platform: "iOS", udid: "A", deviceType: "iPhone-17"),
            .init(name: "iPhone 17", runtimeVersion: "27.2", platform: "iOS", udid: "B", deviceType: "iPhone-17"),
            .init(name: "iPhone 18", runtimeVersion: "27.2", platform: "iOS", udid: "C", deviceType: "iPhone-18"),
            .init(name: "iPhone Duo", runtimeVersion: "27.2", platform: "iOS", udid: "D", deviceType: "iPhone-Duo"),
            .init(name: "iPad Air", runtimeVersion: "27.2", platform: "iOS", udid: "E", deviceType: "iPad-Air"),
            .init(name: "Apple Watch Ultra", runtimeVersion: "12.0", platform: "watchOS", udid: "F", deviceType: "Watch"),
        ])
        catalog.multiDisplayTypes = ["iPhone-Duo"]
        return catalog
    }()

    func choices(_ project: Project) -> SetupChoices {
        SetupChoices.read(container: "App.xcodeproj", containers: ["App.xcodeproj"], containerProblem: nil, in: project, catalog: Self.catalog)
    }

    @Test func eachSchemeSaysWhatItBuildsAndTests() {
        let schemes = choices(project()).schemes
        #expect(schemes.map(\.name) == ["App", "Core"])
        #expect(schemes.map(\.roles) == [[.app, .unitTests, .uiTests], [.unitTests]])
        #expect(schemes.map(\.app) == ["App", nil])
        #expect(schemes.map(\.container) == ["App.xcodeproj", "App.xcodeproj"])
    }

    @Test func thePicksAreWhatSetupWouldWrite() {
        #expect(choices(project()).picks == SetupChoices.Picks(appScheme: "App", uiScheme: "App", testScheme: "App", bundleID: "dev.example.App", testSimulator: "iPhone 18"))
    }

    @Test func aBundleIDBuiltFromASettingIsLeftEmpty() {
        let spec = Self.spec.replacing("\"dev.example.App\"", with: "\"$(BASE_ID).App\"")
        #expect(choices(project(spec: spec)).picks.bundleID == nil)
    }

    @Test func onlyInstalledIOSSimulatorsAreOfferedEachOnce() {
        #expect(choices(project()).simulators == [
            .init(name: "iPhone 17", runtime: "27.2"), .init(name: "iPhone 18", runtime: "27.2"),
            .init(name: "iPhone Duo", runtime: "27.2", twoDisplays: true), .init(name: "iPad Air", runtime: "27.2"),
        ])
    }

    @Test func noSharedSchemeOffersNone() {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write(Self.spec, to: "App.xcodeproj/project.xcproj")
        let choices = choices(project)
        #expect(choices.schemes.isEmpty)
        #expect(choices.picks.appScheme == nil)
    }

    @Test func theConfigSaysWhoseItIs() throws {
        let project = project()
        #expect(choices(project).config == nil)
        project.write("schemaVersion: 1\nsessionDefaults:\n  scheme: Mine\n", to: ".mobilebuildmcp/config.yaml")
        #expect(choices(project).config == .init(owner: .other, scheme: "Mine"))
        _ = try ConfigWriter.write(ProfileAnswers(container: "App.xcodeproj", testSimulator: "iPhone 18", appScheme: "App"), to: project, force: true)
        #expect(choices(project).config?.owner == .xcrew)
    }

    /// A workspace whose own `App` scheme and its project's both build the app: one scheme by name, not two.
    @Test func anAppSchemeTheWorkspaceAndItsProjectBothShareIsStillPicked() {
        let project = project()
        project.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Workspace version = \"1.0\"><FileRef location = \"group:App.xcodeproj\"></FileRef></Workspace>\n", to: "App.xcworkspace/contents.xcworkspacedata")
        project.writeScheme("App", building: ["App"], testing: ["AppTests", "AppUITests"], folder: "App.xcworkspace/xcshareddata")
        let choices = SetupChoices.read(container: "App.xcworkspace", containers: ["App.xcworkspace"], containerProblem: nil, in: project, catalog: Self.catalog)
        #expect(choices.picks.appScheme == "App")
        #expect(choices.picks.bundleID == "dev.example.App")
    }

    /// Two projects with a target called `App`: the bundle ID is the one of the project the scheme builds from.
    @Test func theBundleIDComesFromTheProjectTheSchemeBuilds() {
        let project = Project.temporary(containing: ["Demo.xcodeproj", "App.xcodeproj"])
        project.write(Self.spec.replacing("dev.example.App", with: "dev.example.Demo"), to: "Demo.xcodeproj/project.xcproj")
        project.write(Self.spec, to: "App.xcodeproj/project.xcproj")
        project.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Workspace version = \"1.0\"><FileRef location = \"group:Demo.xcodeproj\"></FileRef><FileRef location = \"group:App.xcodeproj\"></FileRef></Workspace>\n", to: "App.xcworkspace/contents.xcworkspacedata")
        project.writeScheme("App", building: ["App"], container: "App.xcodeproj", folder: "App.xcworkspace/xcshareddata")
        let choices = SetupChoices.read(container: "App.xcworkspace", containers: ["App.xcworkspace"], containerProblem: nil, in: project, catalog: Self.catalog)
        #expect(choices.picks.bundleID == "dev.example.App")
    }
}
