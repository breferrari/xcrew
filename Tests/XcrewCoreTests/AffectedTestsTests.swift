import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// Which tests a change can break, by the targets that own the changed files and every target that depends on them. A
/// false "skip this" lets broken code look green, so whatever the reading doesn't model means running everything.
@Suite struct AffectedTestsTests {
    /// A project in Xcode 27.2's JSON format: `App` depends on `Feature`, which depends on `Core`. `CoreTests` tests
    /// `Core`; `AppTests` tests `App` and runs in it; `FeatureTests` tests `Feature`.
    static let chain = """
        {
          "files": [
            { "kind": "folder", "path": "Core", "target-membership": [ "Core" ] },
            { "kind": "folder", "path": "Feature", "target-membership": [ "Feature" ] },
            { "kind": "folder", "path": "App", "target-membership": [ "App" ] },
            { "kind": "folder", "path": "CoreTests", "target-membership": [ "CoreTests" ] },
            { "kind": "folder", "path": "FeatureTests", "target-membership": [ "FeatureTests" ] },
            { "kind": "folder", "path": "AppTests", "target-membership": [ "AppTests" ] },
            { "kind": "group", "name": "Assets", "path": "Assets", "children": [
              { "path": "Logo.png", "target-membership": [ { "build-phase": "App/resources" } ] },
              { "path": "Unused.png" },
            ] },
          ],
          "targets": [
            { "name": "Core", "id": "C", "product-type": "framework" },
            { "name": "Feature", "id": "F", "product-type": "framework", "dependencies": [ "Core" ] },
            { "name": "App", "id": "A", "product-type": "application", "dependencies": [ "Feature" ] },
            { "name": "CoreTests", "id": "CT", "product-type": "bundle.unit-test", "dependencies": [ "Core" ] },
            { "name": "FeatureTests", "id": "FT", "product-type": "bundle.unit-test", "dependencies": [ "Feature" ] },
            { "name": "AppTests", "id": "AT", "product-type": "bundle.unit-test", "test-host-target": "App" },
          ],
        }
        """

    func project() -> Project {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write(Self.chain, to: "App.xcodeproj/project.xcproj")
        for file in ["Core/Store.swift", "Feature/Screen.swift", "App/AppApp.swift", "AppTests/AppTests.swift", "Assets/Logo.png", "Assets/Unused.png"] {
            project.write("\n", to: file)
        }
        return project
    }

    @Test func aChangeAtTheBottomOfAChainSelectsEveryTestAboveIt() {
        let affected = AffectedTests.of(changed: ["Core/Store.swift"], in: project())
        #expect(affected.selections == ["AppTests", "CoreTests", "FeatureTests"])
        #expect(affected.runAll == nil)
    }

    @Test func aChangeAtTheTopSelectsOnlyItsOwnTests() {
        #expect(AffectedTests.of(changed: ["App/AppApp.swift"], in: project()).selections == ["AppTests"])
        #expect(AffectedTests.of(changed: ["AppTests/AppTests.swift"], in: project()).selections == ["AppTests"])
        #expect(AffectedTests.of(changed: ["Assets/Logo.png"], in: project()).selections == ["AppTests"])
    }

    /// Each of these is something the reading doesn't model: running everything is the only answer that can't be wrong.
    @Test(arguments: [
        "App.xcodeproj/project.xcproj", "App.xcodeproj/xcshareddata/xcschemes/App.xcscheme", "Config/Base.xcconfig",
        "Package.swift", "Package.resolved", "App.xctestplan", "Assets/Unused.png", "README.md", "scripts/lint.sh",
    ])
    func whatTheReadingDoesntModelRunsEverything(_ file: String) {
        let affected = AffectedTests.of(changed: [file], in: project())
        #expect(affected.selections == nil)
        #expect(affected.runAll?.contains(file) == true, "\(affected.runAll ?? "no reason")")
    }

    @Test func oneFileThatRunsEverythingOutweighsTheRest() {
        let affected = AffectedTests.of(changed: ["App/AppApp.swift", "Package.resolved"], in: project())
        #expect(affected.selections == nil)
    }

    @Test func aProjectThatCantBeReadRunsEverything() {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write("{ not json", to: "App.xcodeproj/project.xcproj")
        project.write("\n", to: "App/AppApp.swift")
        let affected = AffectedTests.of(changed: ["App/AppApp.swift"], in: project)
        #expect(affected.selections == nil)
        #expect(affected.runAll?.contains("App.xcodeproj") == true)
    }

    @Test func noChangeSelectsNothing() {
        let affected = AffectedTests.of(changed: [], in: project())
        #expect(affected.selections == [])
        #expect(affected.runAll == nil)
    }
}
