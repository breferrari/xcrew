import Foundation
import Testing

@testable import XcrewCore

@Suite struct CarriedDefaultsTests {
    /// What setup sets itself is never carried over it: the keys `render` writes, in a profile and in the global defaults,
    /// for a workspace and for a project.
    @Test func theKeysSetupSetsAreTheOnesRenderWrites() {
        var inProfiles: Set<String> = []
        var globally: Set<String> = []
        for container in ["App.xcworkspace", "App.xcodeproj"] {
            let answers = ProfileAnswers(container: container, testSimulator: "iPhone 18", appScheme: "App", bundleID: "com.example.app", testScheme: "AppTests")
            let profiles = CarriedDefaults(ConfigRenderer.render(answers, root: URL(fileURLWithPath: "/work"), simulatorIDs: ["iPhone 18": "U18"]))
            inProfiles.formUnion(profiles.profiles.values.joined().map(\.key))
            let global = CarriedDefaults(ConfigRenderer.render(.init(container: container, testSimulator: "iPhone 18"), root: URL(fileURLWithPath: "/work"), simulatorIDs: ["iPhone 18": "U18"]))
            globally.formUnion(global.global.map(\.key))
        }
        #expect(inProfiles == CarriedDefaults.setInProfiles)
        #expect(globally == CarriedDefaults.setGlobally)
    }
}
