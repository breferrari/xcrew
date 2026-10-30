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

    /// A UI test bundle is said apart from the unit tests: a simulator and the app run it, not the unit tests' host alone.
    @Test func aUITestBundleIsSaidApart() {
        let project = project()
        let withUI = Self.chain
            .replacingOccurrences(of: #"{ "kind": "folder", "path": "AppTests", "target-membership": [ "AppTests" ] },"#, with: #"{ "kind": "folder", "path": "AppTests", "target-membership": [ "AppTests" ] }, { "kind": "folder", "path": "AppUITests", "target-membership": [ "AppUITests" ] },"#)
            .replacingOccurrences(of: #"{ "name": "AppTests", "id": "AT", "product-type": "bundle.unit-test", "test-host-target": "App" },"#, with: #"{ "name": "AppTests", "id": "AT", "product-type": "bundle.unit-test", "test-host-target": "App" }, { "name": "AppUITests", "id": "AU", "product-type": "bundle.ui-testing", "dependencies": [ "App" ] },"#)
        project.write(withUI, to: "App.xcodeproj/project.xcproj")
        let affected = AffectedTests.of(changed: ["Core/Store.swift"], in: project)
        #expect(affected.selections == ["AppTests", "AppUITests", "CoreTests", "FeatureTests"])
        #expect(affected.uiSelections == ["AppUITests"])
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

    /// A UI test bundle of one name in two projects stays a UI test bundle once the two are read as one.
    @Test func aUITestBundleInTwoProjectsStaysOne() {
        let project = Project.temporary(containing: ["App.xcworkspace", "A/A.xcodeproj", "B/B.xcodeproj"])
        project.write(#"<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><FileRef location="group:A/A.xcodeproj"/><FileRef location="group:B/B.xcodeproj"/></Workspace>"#, to: "App.xcworkspace/contents.xcworkspacedata")
        project.write(json(#"{ "kind": "folder", "path": "Lib", "target-membership": [ "Lib" ] }"#, #"{ "name": "Lib", "id": "L", "product-type": "framework" }, { "name": "Checks", "id": "C", "product-type": "bundle.ui-testing", "dependencies": [ "Lib" ] }"#), to: "A/A.xcodeproj/project.xcproj")
        project.write(json("", #"{ "name": "Checks", "id": "C2", "product-type": "bundle.ui-testing" }"#), to: "B/B.xcodeproj/project.xcproj")
        #expect(AffectedTests.of(changed: ["A/Lib/Thing.swift"], in: project).uiSelections == ["Checks"])
    }
}

/// A target that links a product no project here builds depends on something unread: everything runs.
@Suite struct AffectedTestsUnreadProductTests {
    @Test func linkingAProductNothingHereBuildsRunsEverything() {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write("""
            { "files": [ { "kind": "group", "name": "Products", "children": [ { "path": "<PRODUCTS>/Elsewhere.framework", "target-membership": [ { "build-phase": "App/frameworks" } ] } ] },
                         { "kind": "folder", "path": "App", "target-membership": [ "App" ] } ],
              "targets": [ { "name": "App", "id": "A", "product-type": "application" }, { "name": "AppTests", "id": "T", "product-type": "bundle.unit-test", "test-host-target": "App" } ] }
            """, to: "App.xcodeproj/project.xcproj")
        let affected = AffectedTests.of(changed: ["App/AppApp.swift"], in: project)
        #expect(affected.selections == nil)
        #expect(affected.runAll?.contains("Elsewhere.framework") == true)
    }
}

/// A dependency entry can point into another project: a proxy whose container is that project's file. It resolves by
/// the target it names, among the projects the workspace reads.
@Suite struct AffectedTestsProxyTests {
    /// A project in the classic format: `framework` with its folder and tests, depending on `dependency` in `../A`.
    func pbxproj(_ name: String, dependency: String?) -> String {
        let external = dependency.map { """
            FD = { isa = PBXTargetDependency; name = \($0); targetProxy = FP; };
            FP = { isa = PBXContainerItemProxy; containerPortal = AR; proxyType = 1; remoteGlobalIDString = X; remoteInfo = \($0); };
            AR = { isa = PBXFileReference; lastKnownFileType = "wrapper.pb-project"; path = "../A/A.xcodeproj"; sourceTree = "<group>"; };
            """ } ?? ""
        return """
            // !$*UTF8*$!
            {
                archiveVersion = 1;
                objectVersion = 77;
                rootObject = P;
                objects = {
                    P = { isa = PBXProject; mainGroup = G; targets = (T, TT); };
                    G = { isa = PBXGroup; children = (F); sourceTree = "<group>"; };
                    F = { isa = PBXFileSystemSynchronizedRootGroup; path = \(name); sourceTree = "<group>"; };
                    T = { isa = PBXNativeTarget; name = \(name); productType = "com.apple.product-type.framework"; fileSystemSynchronizedGroups = (F); buildPhases = (); dependencies = (\(dependency == nil ? "" : "FD")); };
                    TT = { isa = PBXNativeTarget; name = \(name)Tests; productType = "com.apple.product-type.bundle.unit-test"; buildPhases = (); dependencies = (LD); };
                    LD = { isa = PBXTargetDependency; target = T; targetProxy = LP; };
                    LP = { isa = PBXContainerItemProxy; containerPortal = P; proxyType = 1; remoteGlobalIDString = T; remoteInfo = \(name); };
                    \(external)
                };
            }
            """
    }

    func workspace(featureDependsOn dependency: String) -> Project {
        let project = Project.temporary(containing: ["App.xcworkspace", "A/A.xcodeproj", "B/B.xcodeproj"])
        project.write(#"<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><FileRef location="group:A/A.xcodeproj"/><FileRef location="group:B/B.xcodeproj"/></Workspace>"#, to: "App.xcworkspace/contents.xcworkspacedata")
        project.write(pbxproj("Core", dependency: nil), to: "A/A.xcodeproj/project.pbxproj")
        project.write(pbxproj("Feature", dependency: dependency), to: "B/B.xcodeproj/project.pbxproj")
        return project
    }

    @Test func aDependencyIntoAnotherProjectIsFollowed() {
        let affected = AffectedTests.of(changed: ["A/Core/Store.swift"], in: workspace(featureDependsOn: "Core"))
        #expect(affected.selections == ["CoreTests", "FeatureTests"], "\(affected.runAll ?? "")")
    }

    @Test func aDependencyOnATargetNoProjectHereBuildsRunsEverything() {
        let affected = AffectedTests.of(changed: ["A/Core/Store.swift"], in: workspace(featureDependsOn: "Missing"))
        #expect(affected.selections == nil)
        #expect(affected.runAll?.contains("Missing") == true)
    }
}

/// What a link is, and how far it resolves: only another target's product, found in any project the workspace reads.
@Suite struct AffectedTestsLinkTests {
    func json(_ files: String, _ targets: String) -> String {
        "{ \"files\": [ \(files) ], \"targets\": [ \(targets) ] }"
    }

    /// A system framework is no product of the project's: linking it depends on nothing a change here could break.
    @Test func linkingASystemFrameworkIsNoDependency() {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write(json("""
            { "kind": "group", "name": "Frameworks", "children": [ { "path": "<SDKROOT>/System/Library/Frameworks/StoreKit.framework", "target-membership": [ { "build-phase": "App/frameworks" } ] } ] },
            { "kind": "folder", "path": "App", "target-membership": [ "App" ] }
            """, #"{ "name": "App", "id": "A", "product-type": "application" }, { "name": "AppTests", "id": "T", "product-type": "bundle.unit-test", "test-host-target": "App" }"#), to: "App.xcodeproj/project.xcproj")
        #expect(AffectedTests.of(changed: ["App/AppApp.swift"], in: project).selections == ["AppTests"])
    }

    /// A file a script writes to the build folder and a target compiles is no product another target builds.
    @Test func aGeneratedFileInTheBuildFolderIsNoLink() {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write("""
            // !$*UTF8*$!
            {
                archiveVersion = 1;
                objectVersion = 77;
                rootObject = P;
                objects = {
                    P = { isa = PBXProject; mainGroup = G; targets = (T, TT); };
                    G = { isa = PBXGroup; children = (F, GEN); sourceTree = "<group>"; };
                    F = { isa = PBXFileSystemSynchronizedRootGroup; path = App; sourceTree = "<group>"; };
                    GEN = { isa = PBXFileReference; path = Generated.swift; sourceTree = BUILT_PRODUCTS_DIR; };
                    GB = { isa = PBXBuildFile; fileRef = GEN; };
                    S = { isa = PBXSourcesBuildPhase; files = (GB); };
                    T = { isa = PBXNativeTarget; name = App; productType = "com.apple.product-type.application"; fileSystemSynchronizedGroups = (F); buildPhases = (S); dependencies = (); };
                    TT = { isa = PBXNativeTarget; name = AppTests; productType = "com.apple.product-type.bundle.unit-test"; buildPhases = (); dependencies = (LD); };
                    LD = { isa = PBXTargetDependency; target = T; targetProxy = LP; };
                    LP = { isa = PBXContainerItemProxy; containerPortal = P; proxyType = 1; remoteGlobalIDString = T; remoteInfo = App; };
                };
            }
            """, to: "App.xcodeproj/project.pbxproj")
        #expect(AffectedTests.of(changed: ["App/AppApp.swift"], in: project).selections == ["AppTests"])
    }

    /// A module's tests can run in an app another project builds: the host resolves across the workspace.
    @Test func aTestHostInAnotherProjectResolves() {
        let project = Project.temporary(containing: ["App.xcworkspace", "A/A.xcodeproj", "B/B.xcodeproj"])
        project.write(#"<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><FileRef location="group:A/A.xcodeproj"/><FileRef location="group:B/B.xcodeproj"/></Workspace>"#, to: "App.xcworkspace/contents.xcworkspacedata")
        project.write(json(#"{ "kind": "group", "name": "Products", "children": [ { "path": "<PRODUCTS>/App.app" } ] }, { "kind": "folder", "path": "App", "target-membership": [ "App" ] }"#,
                           #"{ "name": "App", "id": "A", "product": "Products/App.app", "product-type": "application" }"#), to: "A/A.xcodeproj/project.xcproj")
        project.write("""
            // !$*UTF8*$!
            {
                archiveVersion = 1;
                objectVersion = 77;
                rootObject = P;
                objects = {
                    P = { isa = PBXProject; mainGroup = G; targets = (TT); };
                    G = { isa = PBXGroup; children = (); sourceTree = "<group>"; };
                    TT = { isa = PBXNativeTarget; name = FeatureTests; productType = "com.apple.product-type.bundle.unit-test"; buildPhases = (); dependencies = (); buildConfigurationList = L; };
                    L = { isa = XCConfigurationList; buildConfigurations = (D); };
                    D = { isa = XCBuildConfiguration; name = Debug; buildSettings = { TEST_HOST = "$(BUILT_PRODUCTS_DIR)/App.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/App"; }; };
                };
            }
            """, to: "B/B.xcodeproj/project.pbxproj")
        #expect(AffectedTests.of(changed: ["A/App/AppApp.swift"], in: project).selections == ["FeatureTests"])
    }

    /// The JSON format names a dependency in another project by its target, as a proxy does in the classic one.
    @Test func aJSONDependencyOnAnotherProjectsTargetResolves() {
        let project = Project.temporary(containing: ["App.xcworkspace", "A/A.xcodeproj", "B/B.xcodeproj"])
        project.write(#"<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><FileRef location="group:A/A.xcodeproj"/><FileRef location="group:B/B.xcodeproj"/></Workspace>"#, to: "App.xcworkspace/contents.xcworkspacedata")
        project.write(json(#"{ "kind": "folder", "path": "Core", "target-membership": [ "Core" ] }"#, #"{ "name": "Core", "id": "C", "product-type": "framework" }"#), to: "A/A.xcodeproj/project.xcproj")
        project.write(json("", #"{ "name": "Feature", "id": "F", "product-type": "framework", "dependencies": [ "Core" ] }, { "name": "FeatureTests", "id": "FT", "product-type": "bundle.unit-test", "dependencies": [ "Feature" ] }"#), to: "B/B.xcodeproj/project.xcproj")
        #expect(AffectedTests.of(changed: ["A/Core/Store.swift"], in: project).selections == ["FeatureTests"])
    }
}
