import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

@Suite struct ProjectTests {
    func machine(_ environment: [String: String]) -> Machine {
        Machine(environment: environment, home: URL(fileURLWithPath: "/"), runner: FakeRunner())
    }

    @Test func mcsProjectWinsOverClaudeProjectDir() {
        #expect(Project.current(machine: machine(["MCS_PROJECT_PATH": "/a", "CLAUDE_PROJECT_DIR": "/b"])).root.path == "/a")
        #expect(Project.current(machine: machine(["CLAUDE_PROJECT_DIR": "/b"])).root.path == "/b")
        #expect(Project.current(machine: machine(["MCS_PROJECT_PATH": ""])).root.path == FileManager.default.currentDirectoryPath)
    }

    @Test func workspacesComeBeforeProjects() {
        let project = Project.temporary(containing: ["Z.xcworkspace", "A.xcodeproj", "B.xcworkspace", "Notes"])
        #expect(project.xcodeContainers == ["B.xcworkspace", "Z.xcworkspace", "A.xcodeproj"])
    }

    @Test(arguments: ["Package.swift", "Project.swift", "Workspace.swift", "project.yml"])
    func recognisesApplePlatformProjects(marker: String) {
        let project = Project.temporary()
        #expect(!project.isApplePlatformProject)
        project.write("", to: marker)
        #expect(project.isApplePlatformProject)
    }

    @Test(arguments: ["ios/Tuist.swift", "apps/ios/App.xcodeproj", "apps/ios/App.xcworkspace"])
    func anAppAFolderOrTwoDownInARepositoryIsAnApplePlatformProject(path: String) {
        #expect(Project.temporary(containing: [".git", path]).isApplePlatformProject)
    }

    @Test func anAppBelowARootOutsideGitIsntLookedFor() {
        // Session start looks below the root only in a repository, so it never walks a folder like Downloads.
        #expect(!Project.temporary(containing: ["apps/ios/App.xcodeproj"]).isApplePlatformProject)
        #expect(Project.temporary(containing: ["App.xcodeproj"]).isApplePlatformProject)
    }

    @Test func aWorktreesGitFileCountsAsARepository() {
        let project = Project.temporary(containing: ["apps/ios/App.xcodeproj"])
        project.write("gitdir: ../main/.git/worktrees/app\n", to: ".git")
        #expect(project.isApplePlatformProject)
    }

    @Test func theHomeFolderIsntSearchedEvenInGit() {
        // Dotfiles kept in git put a .git in the home folder; below it are Desktop, Documents and Downloads.
        let folder = Project.temporary(containing: [".git", "apps/ios/App.xcodeproj"])
        let home = Project(root: folder.root, home: folder.root)
        #expect(home.searchDepth == 0)
        #expect(!home.isApplePlatformProject)
    }

    @Test func anotherProjectsManifestsInADependencyDontCount() {
        #expect(!Project.temporary(containing: [".git", "node_modules/x/Project.swift", "Pods/y/Y.xcodeproj"]).isApplePlatformProject)
    }

    @Test func aSwiftPackageBelowTheRootIsntAnApp() {
        // A repository that keeps a tool or a server in a package is not an Apple-platform app.
        #expect(!Project.temporary(containing: [".git", "tools/format/Package.swift"]).isApplePlatformProject)
    }
}

@Suite struct GeneratedProjectTests {
    @Test(arguments: ["Project.swift", "Workspace.swift", "Tuist", "Tuist.swift", "project.yml"])
    func aGeneratorManifestAtTheRootMarksAGeneratedProject(marker: String) {
        #expect(Project.temporary(containing: [marker]).isGenerated)
    }

    @Test func aTuistProjectInASubfolderCounts() {
        #expect(Project.temporary(containing: ["ios/Tuist.swift"]).isTuistProject)
        #expect(Project.temporary(containing: ["apps/ios/Project.swift"]).isTuistProject)
        #expect(Project.temporary(containing: ["apps/ios/project.yml"]).isGenerated)
    }

    @Test func aClassicProjectIsNeither() {
        let project = Project.temporary(containing: ["App.xcodeproj", "Sources"])
        #expect(!project.isGenerated)
        #expect(!project.isTuistProject)
    }

    @Test func aManifestCountsWhateverItsCase() {
        #expect(Project.temporary(containing: ["Project.yml"]).isGenerated)
    }

    @Test func bundlesArentSearched() {
        #expect(!Project.temporary(containing: ["App.xcodeproj", "App/Assets.xcassets/Tuist"]).isGenerated)
    }

    @Test func dependenciesDontCount() {
        // A checked-out package that uses Tuist isn't this project being generated.
        #expect(!Project.temporary(containing: ["node_modules/x/Project.swift", ".build/checkouts/y/Tuist"]).isGenerated)
    }
}
