import Foundation
import Testing
@testable import XcrewCLI
import XcrewCore
import XcrewTestSupport

/// `xcrew graph` in words and as JSON, and `--owner` for one file.
@Suite struct GraphCommandTests {
    /// `App` on `Feature` on `Core`, in Xcode 27.2's JSON format; App's source imports Core, which it reaches only
    /// through Feature.
    func project() -> Project {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write("""
            {
              "files": [
                { "kind": "folder", "path": "Core", "target-membership": [ "Core" ] },
                { "kind": "folder", "path": "Feature", "target-membership": [ "Feature" ] },
                { "kind": "folder", "path": "App", "target-membership": [ "App" ] },
              ],
              "targets": [
                { "name": "Core", "id": "C", "product-type": "framework", "product": "Products/Core.framework" },
                { "name": "Feature", "id": "F", "product-type": "framework", "product": "Products/Feature.framework", "dependencies": [ "Core" ] },
                { "name": "App", "id": "A", "product-type": "application", "product": "Products/App.app", "dependencies": [ "Feature" ] },
                { "name": "AppTests", "id": "AT", "product-type": "bundle.unit-test", "product": "Products/AppTests.xctest", "test-host-target": "App" },
              ],
            }
            """, to: "App.xcodeproj/project.xcproj")
        project.write("import Core\n", to: "Feature/Screen.swift")
        project.write("import SwiftUI\nimport Feature\nimport Core\n", to: "App/App.swift")
        return project
    }

    @Test func wordsNameEachModuleAndEachImportThatIsntADirectDependency() async {
        let run = await Run("graph", context: .fake(project: project()))
        #expect(run.status == 0)
        #expect(run.output == [
            "3 modules, as the projects declare them:",
            "  App (application, App.xcodeproj): depends on Feature; tested by AppTests",
            "  Core (framework, App.xcodeproj): depends on nothing",
            "  Feature (framework, App.xcodeproj): depends on Core",
            "Imports of these modules: 2 declared, 1 transitive-only.",
            "  transitive-only: App imports Core at App/App.swift:3",
        ])
    }

    @Test func jsonCarriesTheWholeGraph() async throws {
        let run = await Run("graph", "--json", context: .fake(project: project()))
        let graph = try JSONDecoder().decode(ModuleGraph.self, from: Data(run.text.utf8))
        #expect(graph.modules.map(\.name) == ["App", "Core", "Feature"])
        #expect(graph.imports.map(\.placement) == [.declared, .transitiveOnly, .declared])
        #expect(graph.otherImports == ["SwiftUI": 1])
    }

    @Test func ownerNamesTheTargetsThatBuildAFile() async {
        let project = project()
        #expect(await Run("graph", "--owner", "App/App.swift", context: .fake(project: project)).output == ["App/App.swift: App"])
        #expect(await Run("graph", "--owner", project.root.appending(path: "Core/Store.swift").path, context: .fake(project: project)).output == ["Core/Store.swift: Core"])
        let none = await Run("graph", "--owner", "Notes.md", context: .fake(project: project))
        #expect(none.output == ["Notes.md: no target builds it"])
        #expect(none.status == 0)
    }

    @Test func aWorkspaceItCantReadSaysWhyAndFails() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write("not a project", to: "App.xcodeproj/project.xcproj")
        let run = await Run("graph", context: .fake(project: project))
        #expect(run.status == 1)
        #expect(run.output.first?.hasPrefix("The workspace couldn't be read: App.xcodeproj couldn't be read") == true)
    }
}
