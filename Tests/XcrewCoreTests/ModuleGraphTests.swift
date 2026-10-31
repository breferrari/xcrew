import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// A workspace's modules as its projects declare them, and each import of one of them classed by where it lands in that
/// graph: a direct dependency, reachable only through others, not reachable, or depending on the importer.
@Suite struct ModuleGraphTests {
    /// Xcode 27.2's JSON format: `App` on `Feature` on `Data` on `Core`, each in a folder of its own; `Island` is a
    /// framework nothing depends on; `CoreTests` tests `Core`; `AppUITests` drives `App`.
    static let layers = """
        {
          "files": [
            { "kind": "folder", "path": "Core", "target-membership": [ "Core" ] },
            { "kind": "folder", "path": "Data", "target-membership": [ "Data" ] },
            { "kind": "folder", "path": "Feature", "target-membership": [ "Feature" ] },
            { "kind": "folder", "path": "App", "target-membership": [ "App" ] },
            { "kind": "folder", "path": "Island", "target-membership": [ "Island" ] },
            { "kind": "folder", "path": "CoreTests", "target-membership": [ "CoreTests" ] },
            { "kind": "folder", "path": "AppUITests", "target-membership": [ "AppUITests" ] },
          ],
          "targets": [
            { "name": "Core", "id": "C", "product-type": "framework", "product": "Products/Core.framework" },
            { "name": "Data", "id": "D", "product-type": "framework", "product": "Products/Data.framework", "dependencies": [ "Core" ] },
            { "name": "Feature", "id": "F", "product-type": "framework", "product": "Products/Feature.framework", "dependencies": [ "Data" ] },
            { "name": "App", "id": "A", "product-type": "application", "product": "Products/App.app", "dependencies": [ "Feature" ] },
            { "name": "Island", "id": "I", "product-type": "framework", "product": "Products/Island.framework" },
            { "name": "CoreTests", "id": "CT", "product-type": "bundle.unit-test", "product": "Products/CoreTests.xctest", "dependencies": [ "Core" ] },
            { "name": "AppUITests", "id": "AU", "product-type": "bundle.ui-testing", "product": "Products/AppUITests.xctest", "test-host-target": "App" },
          ],
        }
        """

    func project(_ sources: [String: String], spec: String = layers) -> Project {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write(spec, to: "App.xcodeproj/project.xcproj")
        for (file, text) in sources { project.write(text, to: file) }
        return project
    }

    @Test func eachModuleHasItsKindDependenciesAndTests() {
        let graph = ModuleGraph.read(project([:]))
        #expect(graph.modules.map(\.name) == ["App", "Core", "Data", "Feature", "Island"])
        #expect(graph.modules.first { $0.name == "Data" }.map { [$0.kind, $0.project] + $0.dependencies } == ["framework", "App.xcodeproj", "Core"])
        #expect(graph.modules.first { $0.name == "Core" }?.tests == ["CoreTests"])
        #expect(graph.modules.first { $0.name == "App" }.map { [$0.kind] + $0.tests } == ["application", "AppUITests"])
    }

    @Test func eachImportIsPlacedInTheGraph() {
        let graph = ModuleGraph.read(project([
            "Data/Store.swift": "import Foundation\nimport Core\n",
            "Feature/Screen.swift": "import SwiftUI\nimport Data\nimport Core\nimport Island\n",
            "Core/Back.swift": "#if DEBUG\nimport Feature\n#endif\n",
            "CoreTests/CoreTests.swift": "import Testing\n@testable import Core\n",
        ]))
        #expect(graph.imports == [
            .init(target: "Core", file: "Core/Back.swift", line: 2, module: "Feature", placement: .upward, conditional: true),
            .init(target: "CoreTests", file: "CoreTests/CoreTests.swift", line: 2, module: "Core", placement: .declared),
            .init(target: "Data", file: "Data/Store.swift", line: 2, module: "Core", placement: .declared),
            .init(target: "Feature", file: "Feature/Screen.swift", line: 2, module: "Data", placement: .declared),
            .init(target: "Feature", file: "Feature/Screen.swift", line: 3, module: "Core", placement: .transitiveOnly),
            .init(target: "Feature", file: "Feature/Screen.swift", line: 4, module: "Island", placement: .undeclared),
        ])
        #expect(graph.otherImports == ["Foundation": 1, "SwiftUI": 1, "Testing": 1])
    }

    @Test func aFrameworkDependencyNoSourceImportsIsSaid() {
        let graph = ModuleGraph.read(project(["Data/Store.swift": "import Core\n", "App/App.swift": "import SwiftUI\n"]))
        #expect(graph.unimported == [.init(target: "App", dependency: "Feature"), .init(target: "CoreTests", dependency: "Core"), .init(target: "Feature", dependency: "Data")])
    }

    @Test func aWorkspaceItCantReadGivesOnlyTheReason() {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write("not a project", to: "App.xcodeproj/project.xcproj")
        let graph = ModuleGraph.read(project)
        #expect(graph.unread?.hasPrefix("App.xcodeproj couldn't be read") == true)
        #expect(graph.modules.isEmpty)
    }

    /// Two frameworks named by their products, one with a module name of its own, one built from a setting, and a
    /// folder whose exception set moves one file.
    static let names = """
        {
          "files": [
            { "kind": "folder", "path": "Kit", "target-membership": [ "Kit" ], "membership-exceptions": [ { "target": "Kit", "exclusions": [ "Moved.swift" ] } ] },
            { "kind": "folder", "path": "App", "target-membership": [ "App" ] },
          ],
          "targets": [
            { "name": "Kit", "id": "K", "product-type": "framework", "product": "Products/My-Kit 2.framework" },
            { "name": "Fast", "id": "F", "product-type": "framework", "product": "Products/2Fast.framework" },
            { "name": "Core", "id": "C", "product-type": "framework", "product": "Products/Core.framework", "build-settings": { "PRODUCT_MODULE_NAME": "CoreKit" } },
            { "name": "Odd", "id": "O", "product-type": "framework", "product": "Products/Odd.framework", "build-settings": { "PRODUCT_MODULE_NAME[config=Debug]": "$(ODD_NAME)" } },
            { "name": "App", "id": "A", "product-type": "application", "product": "Products/App.app", "dependencies": [ "Kit", "Fast", "Core" ] },
          ],
        }
        """

    @Test func aModuleIsNamedAsXcodeNamesIt() {
        let graph = ModuleGraph.read(project(["App/App.swift": "import My_Kit_2\nimport _Fast\nimport CoreKit\n"], spec: Self.names))
        #expect(graph.modules.map(\.name) == ["App", "CoreKit", "My_Kit_2", "Odd", "_Fast"])
        #expect(graph.imports.map(\.placement) == [.declared, .declared, .declared])
        #expect(graph.otherImports.isEmpty)
    }

    @Test func whatTheReadingCantSettleIsNoted() {
        #expect(ModuleGraph.read(project(["Kit/Kept.swift": "\n", "Kit/Moved.swift": "\n"], spec: Self.names)).notes == [
            "Odd's module name is set from another setting ($(ODD_NAME)), so imports of it are read under Odd",
            "Kit/Moved.swift has a target membership of its own, which this doesn't read",
        ])
    }

    @Test func aModuleNameSetInEveryConfigurationOfAPBXProjIsUsed() {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write("""
            // !$*UTF8*$!
            { archiveVersion = 1; objects = {
              T1 = { isa = PBXNativeTarget; name = Core; productType = "com.apple.product-type.framework"; buildConfigurationList = L1; };
              L1 = { isa = XCConfigurationList; buildConfigurations = (C1, C2); };
              C1 = { isa = XCBuildConfiguration; name = Debug; buildSettings = { PRODUCT_MODULE_NAME = CoreKit; }; };
              C2 = { isa = XCBuildConfiguration; name = Release; buildSettings = { PRODUCT_MODULE_NAME = CoreKit; }; };
            }; rootObject = T1; }
            """, to: "App.xcodeproj/project.pbxproj")
        #expect(ModuleGraph.read(project).modules.map(\.name) == ["CoreKit"])
    }

    /// A static library's product carries `lib`; two targets build a module named `Core`, one per platform; a module
    /// name set for Debug only; one built with `${}`; an aggregate target.
    static let edges = """
        {
          "files": [
            { "kind": "folder", "path": "Mac", "target-membership": [ "AppMac" ] },
          ],
          "targets": [
            { "name": "Store", "id": "S", "product-type": "library.static", "product": "Products/libStore.a" },
            { "name": "CoreiOS", "id": "CI", "product-type": "framework", "product": "Products/Core.framework" },
            { "name": "CoreMac", "id": "CM", "product-type": "framework", "product": "Products/Core.framework" },
            { "name": "Partial", "id": "P", "product-type": "framework", "product": "Products/Partial.framework", "build-settings": { "PRODUCT_MODULE_NAME[config=Debug]": "PartialKit" } },
            { "name": "Braced", "id": "B", "product-type": "framework", "product": "Products/Braced.framework", "build-settings": { "PRODUCT_MODULE_NAME": "${BRACED}" } },
            { "name": "Lint", "id": "L", "kind": "aggregate" },
            { "name": "AppMac", "id": "AM", "product-type": "application", "product": "Products/AppMac.app", "dependencies": [ "CoreMac", "Store" ] },
          ],
        }
        """

    @Test func aLibraryIsImportedWithoutItsLibPrefix() {
        let graph = ModuleGraph.read(project(["Mac/App.swift": "import Store\n"], spec: Self.edges))
        #expect(graph.imports.map { "\($0.module) \($0.placement)" } == ["Store declared"])
    }

    @Test func aModuleTwoTargetsBuildIsPlacedByTheOneTheImporterDependsOn() {
        for _ in 0..<8 {
            let graph = ModuleGraph.read(project(["Mac/App.swift": "import Core\n"], spec: Self.edges))
            #expect(graph.imports.map(\.placement) == [.declared])
            #expect(!graph.unimported.contains { $0.dependency == "CoreMac" })
        }
    }

    @Test func aModuleNameSetOnlySometimesOrThroughBracesIsNoted() {
        let notes = ModuleGraph.read(project([:], spec: Self.edges)).notes
        #expect(notes.contains("Braced's module name is set from another setting (${BRACED}), so imports of it are read under Braced"))
        #expect(notes.contains("Partial's module name is set for some configurations only (PartialKit), so imports of it are read under Partial"))
    }

    @Test func aTargetWithNoProductIsNoModule() {
        #expect(!ModuleGraph.read(project([:], spec: Self.edges)).modules.contains { $0.target == "Lint" })
    }
}

/// How each dependency arises in `project.pbxproj`, by the phase or setting that makes it: what `graph` keeps and what
/// `affected` reads, and a Swift file a target only copies, which it doesn't build.
@Suite struct ModuleGraphPhasesTests {
    /// `App` links `Feature` and copies it too, only copies `Core`, and names `Data` as a dependency; `AppTests` runs in
    /// `App` through `TEST_HOST`. `Feature` compiles `Feature/Shown.swift` and copies `Feature/Extra.swift` as a resource.
    static let phases = """
        // !$*UTF8*$!
        { archiveVersion = 1; objects = {
          G = { isa = PBXGroup; sourceTree = "<group>"; children = (FS, FX); };
          FS = { isa = PBXFileReference; path = Feature/Shown.swift; sourceTree = "<group>"; };
          FX = { isa = PBXFileReference; path = Feature/Extra.swift; sourceTree = "<group>"; };
          PC = { isa = PBXFileReference; path = Core.framework; sourceTree = BUILT_PRODUCTS_DIR; };
          PD = { isa = PBXFileReference; path = Data.framework; sourceTree = BUILT_PRODUCTS_DIR; };
          PF = { isa = PBXFileReference; path = Feature.framework; sourceTree = BUILT_PRODUCTS_DIR; };
          PA = { isa = PBXFileReference; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
          PT = { isa = PBXFileReference; path = AppTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
          TC = { isa = PBXNativeTarget; name = Core; productType = "com.apple.product-type.framework"; productReference = PC; };
          TD = { isa = PBXNativeTarget; name = Data; productType = "com.apple.product-type.framework"; productReference = PD; };
          TF = { isa = PBXNativeTarget; name = Feature; productType = "com.apple.product-type.framework"; productReference = PF; buildPhases = (FSRC, FRES); };
          FSRC = { isa = PBXSourcesBuildPhase; files = (BFS); };
          BFS = { isa = PBXBuildFile; fileRef = FS; };
          FRES = { isa = PBXResourcesBuildPhase; files = (BFX); };
          BFX = { isa = PBXBuildFile; fileRef = FX; };
          TA = { isa = PBXNativeTarget; name = App; productType = "com.apple.product-type.application"; productReference = PA; buildPhases = (ALINK, AEMBED); dependencies = (DEPD); };
          DEPD = { isa = PBXTargetDependency; target = TD; };
          ALINK = { isa = PBXFrameworksBuildPhase; files = (BLF); };
          BLF = { isa = PBXBuildFile; fileRef = PF; };
          AEMBED = { isa = PBXCopyFilesBuildPhase; files = (BEF, BEC); };
          BEF = { isa = PBXBuildFile; fileRef = PF; };
          BEC = { isa = PBXBuildFile; fileRef = PC; };
          TT = { isa = PBXNativeTarget; name = AppTests; productType = "com.apple.product-type.bundle.unit-test"; productReference = PT; buildConfigurationList = LT; };
          LT = { isa = XCConfigurationList; buildConfigurations = (CT); };
          CT = { isa = XCBuildConfiguration; name = Debug; buildSettings = { TEST_HOST = "$(BUILT_PRODUCTS_DIR)/App.app/App"; }; };
        }; rootObject = G; }
        """

    func project() -> Project {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write(Self.phases, to: "App.xcodeproj/project.pbxproj")
        project.write("import Foundation\n", to: "Feature/Shown.swift")
        project.write("import Data\n", to: "Feature/Extra.swift")
        return project
    }

    /// Embedding alone carries a binary, not a module: the graph's layers are what's linked or named, and a framework
    /// both linked and copied is a dependency. `affected` reads every edge, the test host and the embedded one included.
    @Test func eachEdgeCountsByHowItArises() throws {
        let project = project()
        let graph = ModuleGraph.read(project)
        let app = try #require(graph.modules.first { $0.target == "App" })
        #expect(app.dependencies == ["Data", "Feature"])
        #expect(app.embeds == ["Core"])
        let workspace = try WorkspaceGraph.read(project).get()
        #expect(workspace.targets["App"]?.dependencies == ["Core", "Data", "Feature"])
        #expect(workspace.targets["AppTests"]?.dependencies == ["App"])
    }

    /// A target that copies the app it runs in, as `TEST_HOST` names it, still builds on that app: copying it doesn't
    /// make the test host an embedding alone.
    @Test func aCopiedTestHostIsStillADependency() throws {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write("""
            // !$*UTF8*$!
            { archiveVersion = 1; objects = {
              PA = { isa = PBXFileReference; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
              PX = { isa = PBXFileReference; path = Ext.appex; sourceTree = BUILT_PRODUCTS_DIR; };
              TA = { isa = PBXNativeTarget; name = App; productType = "com.apple.product-type.application"; productReference = PA; };
              TX = { isa = PBXNativeTarget; name = Ext; productType = "com.apple.product-type.framework"; productReference = PX; buildPhases = (COPY); buildConfigurationList = LX; };
              COPY = { isa = PBXCopyFilesBuildPhase; files = (BA); };
              BA = { isa = PBXBuildFile; fileRef = PA; };
              LX = { isa = XCConfigurationList; buildConfigurations = (CX); };
              CX = { isa = XCBuildConfiguration; name = Debug; buildSettings = { TEST_HOST = "$(BUILT_PRODUCTS_DIR)/App.app/App"; }; };
            }; rootObject = TA; }
            """, to: "App.xcodeproj/project.pbxproj")
        let ext = try #require(ModuleGraph.read(project).modules.first { $0.target == "Ext" })
        #expect(ext.dependencies == ["App"])
        #expect(ext.embeds == nil)
    }

    /// A Swift file a target only copies is no source of its: its imports aren't read, and it has no owner that builds it.
    /// `affected` still counts it, since a changed resource changes the target's bundle.
    @Test func aSwiftFileATargetOnlyCopiesIsNoSourceOfIt() throws {
        let project = project()
        let graph = ModuleGraph.read(project)
        #expect(graph.imports.isEmpty)
        #expect(FileOwners.of("Feature/Extra.swift", in: project).targets.isEmpty)
        #expect(FileOwners.of("Feature/Shown.swift", in: project).targets == ["Feature"])
        let workspace = try WorkspaceGraph.read(project).get()
        #expect(workspace.owners(of: ProjectLayout.canonical(project.root.appending(path: "Feature/Extra.swift"))).targets == ["Feature"])
    }

    /// The JSON format names no phase: a product a target is a member of counts as a dependency, as it always has, until
    /// the format is reviewed (docs/findings.md, *The module graph*).
    @Test func theJSONFormatsProductMembershipStillCountsAsADependency() throws {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write("""
            {
              "files": [ { "path": "<PRODUCTS>/Core.framework", "target-membership": [ "App" ] } ],
              "targets": [
                { "name": "Core", "id": "C", "product-type": "framework", "product": "Products/Core.framework" },
                { "name": "App", "id": "A", "product-type": "application", "product": "Products/App.app" },
              ],
            }
            """, to: "App.xcodeproj/project.xcproj")
        let app = try #require(ModuleGraph.read(project).modules.first { $0.target == "App" })
        #expect(app.dependencies == ["Core"])
        #expect(app.embeds == nil)
    }
}
