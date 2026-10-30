import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

@Suite struct ConfigRendererTests {
    let root = URL(fileURLWithPath: "/work/App")

    /// MobileBuildMCP's `xcode-ide` calls any Xcode MCP tool through its own bridge, past the mod's guards, and the
    /// status bar is the one `simulator-management` tool neither `simulator` nor `sim-env` had (docs/findings.md,
    /// *MobileBuildMCP's tool groups*).
    @Test func theToolGroupsLeaveOutXcodeIDEAndCarryTheStatusBar() {
        let yaml = ConfigRenderer.render(.init(container: "App.xcodeproj", testSimulator: "iPhone 17", testScheme: "AppTests"), root: URL(fileURLWithPath: "/work"))
        #expect(yaml.contains("enabledWorkflows:\n  - simulator\n  - sim-env\n  - ui-automation\n  - debugging\n"))
        #expect(yaml.contains("customWorkflows:\n  sim-env:\n    - erase_sims\n    - set_sim_appearance\n    - set_sim_location\n    - reset_sim_location\n    - sim_statusbar\n    - toggle_software_keyboard\n    - toggle_connect_hardware_keyboard\n"))
    }

    @Test func onlyProfilesWithASchemeAreWritten() async {
        let yaml = ConfigRenderer.render(ProfileAnswers(container: "App.xcodeproj", testSimulator: "iPhone 17", appScheme: "App"), root: root)
        #expect(!yaml.contains("  unit:"))
        #expect(yaml.contains("  app:\n    projectPath: './App.xcodeproj'\n    scheme: 'App'"))
        #expect(yaml.hasSuffix("activeSessionDefaultsProfile: app\n"))
    }

    @Test func aTestSchemeMakesUnitTheActiveProfile() async {
        let answers = ProfileAnswers(container: "App.xcworkspace", testSimulator: "iPhone 17", appScheme: "App", testScheme: "App")
        let yaml = ConfigRenderer.render(answers, root: root)
        #expect(yaml.contains("  unit:\n    workspacePath: './App.xcworkspace'\n    scheme: 'App'\n    simulatorName: 'iPhone 17'"))
        #expect(yaml.hasSuffix("activeSessionDefaultsProfile: unit\n"))
    }

    @Test func aUITestSchemeAloneIsActive() async {
        let yaml = ConfigRenderer.render(ProfileAnswers(container: "App.xcworkspace", testSimulator: "iPhone 17", uiTestScheme: "AppUITests"), root: root)
        #expect(yaml.hasSuffix("activeSessionDefaultsProfile: ui\n"))
    }

    @Test func everyProfileCarriesItsSimulatorID() async {
        let answers = ProfileAnswers(container: "App.xcworkspace", testSimulator: "iPhone 17", appSimulator: "iPhone 17 Pro", appScheme: "App", testScheme: "App")
        let yaml = ConfigRenderer.render(answers, root: root, simulatorIDs: ["iPhone 17": "AAAA", "iPhone 17 Pro": "BBBB"])
        #expect(yaml.contains("    simulatorName: 'iPhone 17'\n    simulatorId: 'AAAA'"))
        #expect(yaml.contains("    simulatorName: 'iPhone 17 Pro'\n    simulatorId: 'BBBB'"))
    }

    /// With no scheme yet, the container and simulator still reach MobileBuildMCP as its global defaults.
    @Test func withoutSchemesTheDefaultsAreGlobal() async {
        let yaml = ConfigRenderer.render(ProfileAnswers(container: "App.xcworkspace", testSimulator: "iPhone 17"), root: root, simulatorIDs: ["iPhone 17": "AAAA"])
        #expect(yaml.hasSuffix("sessionDefaults:\n  workspacePath: './App.xcworkspace'\n  simulatorName: 'iPhone 17'\n  simulatorId: 'AAAA'\n"))
        #expect(!yaml.contains("activeSessionDefaultsProfile"))
    }

    /// A config edited by hand may indent by four, carry comments, or end its lines with CRLF.
    @Test func profilesAreReadFromAnyValidIndent() async {
        let yaml = "schemaVersion: 1\r\nsessionDefaultsProfiles:\r\n    unit:\r\n        scheme: App\r\n# the app\r\n    app:\r\n        scheme: App\r\nactiveSessionDefaultsProfile: app\r\n"
        let read = ConfigRenderer.profiles(in: yaml)
        #expect(read.names == ["unit", "app"])
        #expect(read.withScheme == ["unit", "app"])
        #expect(read.active == "app")
    }

    @Test func profilesAreReadBackWithTheActiveOne() async {
        let answers = ProfileAnswers(container: "App.xcworkspace", testSimulator: "iPhone 17", appScheme: "App", uiTestScheme: "AppUITests", testScheme: "App")
        let read = ConfigRenderer.profiles(in: ConfigRenderer.render(answers, root: root))
        #expect(read.names == ["unit", "app", "ui"])
        #expect(read.active == "unit")
    }

    @Test func uiAndAppProfilesWhenSchemesAreGiven() async {
        let answers = ProfileAnswers(
            container: "App.xcworkspace", testSimulator: "iPhone 17", appSimulator: "iPhone 17 Pro",
            appScheme: "App", bundleID: "com.example.app", uiTestScheme: "AppUITests"
        )
        let yaml = ConfigRenderer.render(answers, root: root)
        #expect(yaml.contains("  ui:\n    workspacePath: './App.xcworkspace'\n    scheme: 'AppUITests'\n    simulatorName: 'iPhone 17 Pro'"))
        #expect(yaml.contains("    scheme: 'App'\n    simulatorName: 'iPhone 17 Pro'\n    bundleId: 'com.example.app'"))
    }

    @Test func projectsUseProjectPath() async {
        let yaml = ConfigRenderer.render(ProfileAnswers(container: "./App.xcodeproj", testSimulator: "iPhone 17", appScheme: "App"), root: root)
        #expect(yaml.contains("projectPath: './App.xcodeproj'"))
    }

    @Test func emptyAnswersCountAsMissing() async {
        let answers = ProfileAnswers(container: "A.xcworkspace", testSimulator: "iPhone 17", appSimulator: "", appScheme: "", uiTestScheme: "", testScheme: "")
        #expect(answers.appSimulator == "iPhone 17")
        #expect(answers.appScheme == nil)
        #expect(answers.uiTestScheme == nil)
        #expect(answers.testScheme == nil)
    }

    @Test func quotingSurvivesYAMLSpecialCharacters() async {
        let name = "Bob's iPhone: #2"
        let yaml = ConfigRenderer.render(ProfileAnswers(container: "A.xcworkspace", testSimulator: name, testScheme: "A"), root: root)
        #expect(yaml.contains("simulatorName: 'Bob''s iPhone: #2'"))
        #expect(ConfigRenderer.simulatorNames(in: yaml) == [name])
    }
}
