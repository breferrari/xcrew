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

/// What the first reading missed, each a skip that wasn't safe.
@Suite struct AffectedTestsEdgeTests {
    func json(_ files: String, _ targets: String) -> String {
        "{ \"files\": [ \(files) ], \"targets\": [ \(targets) ] }"
    }

    /// A target that links another's product depends on it, with no dependency entry: Xcode finds it implicitly.
    @Test func linkingAProductIsDependingOnIt() {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write(json("""
            { "kind": "group", "name": "Products", "children": [ { "path": "<PRODUCTS>/Core.framework", "target-membership": [ { "build-phase": "App/frameworks" } ] } ] },
            { "kind": "folder", "path": "Core", "target-membership": [ "Core" ] }, { "kind": "folder", "path": "App", "target-membership": [ "App" ] }
            """, """
            { "name": "Core", "id": "C", "product": "Products/Core.framework", "product-type": "framework" }, { "name": "App", "id": "A", "product-type": "application" },
            { "name": "AppTests", "id": "T", "product-type": "bundle.unit-test", "test-host-target": "App" }
            """), to: "App.xcodeproj/project.xcproj")
        #expect(AffectedTests.of(changed: ["Core/Store.swift"], in: project).selections == ["AppTests"])
    }

    /// An exception set can name a subfolder: every file under it has a membership of its own.
    @Test func anExceptedSubfolderCoversItsFiles() {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write(json("""
            { "kind": "folder", "path": "Shared", "target-membership": [ "App" ], "membership-exceptions": [ { "target": "Widget", "inclusions": [ "Models" ] } ] }
            """, #"{ "name": "App", "id": "A", "product-type": "application" }, { "name": "Widget", "id": "W", "product-type": "app-extension" }"#), to: "App.xcodeproj/project.xcproj")
        #expect(AffectedTests.of(changed: ["Shared/Models/Item.swift"], in: project).selections == nil)
    }

    /// A file inside a bundle the project lists whole, an asset catalog say, belongs to that bundle's targets.
    @Test func aFileInsideAnOwnedBundleIsTheBundles() {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write(json("""
            { "kind": "group", "path": "App", "children": [ { "path": "Assets.xcassets", "target-membership": [ { "build-phase": "App/resources" } ] } ] }
            """, #"{ "name": "App", "id": "A", "product-type": "application" }, { "name": "AppTests", "id": "T", "product-type": "bundle.unit-test", "test-host-target": "App" }"#), to: "App.xcodeproj/project.xcproj")
        #expect(AffectedTests.of(changed: ["App/Assets.xcassets/Logo.imageset/Contents.json"], in: project).selections == ["AppTests"])
    }

    /// A workspace can keep a project inside a group, whose location is the group's: it's read like the others.
    @Test func aProjectInAWorkspaceGroupIsRead() {
        let project = Project.temporary(containing: ["App.xcworkspace", "Modules/Feature/Feature.xcodeproj"])
        project.write(#"<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><Group location="group:Modules" name="Modules"><FileRef location="group:Feature/Feature.xcodeproj"/></Group></Workspace>"#, to: "App.xcworkspace/contents.xcworkspacedata")
        project.write("{ not json", to: "Modules/Feature/Feature.xcodeproj/project.xcproj")
        #expect(AffectedTests.of(changed: ["Modules/Feature/Screen.swift"], in: project).runAll?.contains("Modules/Feature/Feature.xcodeproj") == true)
    }

    /// Two projects with a target of the same name: neither's dependencies are dropped.
    @Test func sameNamedTargetsInTwoProjectsKeepEveryDependency() {
        let project = Project.temporary(containing: ["App.xcworkspace", "A/A.xcodeproj", "B/B.xcodeproj"])
        project.write(#"<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><FileRef location="group:A/A.xcodeproj"/><FileRef location="group:B/B.xcodeproj"/></Workspace>"#, to: "App.xcworkspace/contents.xcworkspacedata")
        project.write(json(#"{ "kind": "folder", "path": "Lib", "target-membership": [ "Lib" ] }"#, #"{ "name": "Lib", "id": "L", "product-type": "framework" }, { "name": "Checks", "id": "C", "product-type": "bundle.unit-test" }"#), to: "A/A.xcodeproj/project.xcproj")
        project.write(json("", #"{ "name": "Checks", "id": "C2", "product-type": "bundle.unit-test", "dependencies": [ "Lib" ] }, { "name": "Lib", "id": "L2", "product-type": "framework" }"#), to: "B/B.xcodeproj/project.xcproj")
        #expect(AffectedTests.of(changed: ["A/Lib/Thing.swift"], in: project).selections == ["Checks"])
    }
}
