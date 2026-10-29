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

    @Test func aFolderWithADotInItsNameIsSearched() {
        #expect(Project.temporary(containing: [".git", "apps/MyApp.iOS/App.xcodeproj"]).isApplePlatformProject)
    }

    @Test func aSymlinkedSpellingOfHomeIsHome() throws {
        let folder = Project.temporary(containing: [".git", "apps/ios/App.xcodeproj", "ios/Tuist.swift"]).root
        let link = FileManager.default.temporaryDirectory.appending(path: "xcrew-tests-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        defer { try? FileManager.default.removeItem(at: link) }
        let project = Project(root: folder, home: link)
        #expect(!project.isApplePlatformProject)
        #expect(!project.isGenerated)
    }

    // Pins for docs/findings.md, "How Foundation sees a project's folders".

    @Test func theDataVolumesFirmlinkAndLetterCaseNameTheHomeFolder() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let firmlinked = URL(fileURLWithPath: "/System/Volumes/Data" + home.path)
        #expect(ProjectLayout.canonical(firmlinked) == ProjectLayout.canonical(home))
        let caseSensitive = try? home.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames
        if caseSensitive == false {
            #expect(ProjectLayout.canonical(URL(fileURLWithPath: home.path.uppercased())) == ProjectLayout.canonical(home))
        }
    }

    @Test func anAssetCatalogIsntAPackageButIsntSearched() throws {
        let project = Project.temporary(containing: ["App.xcodeproj", "Assets.xcassets", "MyApp.iOS"])
        let package = { (name: String) in try project.root.appending(path: name).resourceValues(forKeys: [.isPackageKey]).isPackage }
        #expect(try package("App.xcodeproj") == true)
        #expect(try package("Assets.xcassets") == false)
        #expect(try package("MyApp.iOS") == false)
        #expect(!ProjectLayout.isSearched(project.root.appending(path: "Assets.xcassets")))
        #expect(ProjectLayout.isSearched(project.root.appending(path: "MyApp.iOS")))
    }

    @Test func aProjectOpenedThroughASymlinkIsFound() throws {
        // Listing a URL doesn't follow a symlink at its end, so the walk starts from the resolved root.
        let folder = Project.temporary(containing: [".git", "App.xcodeproj", "apps/ios/Tuist.swift"]).root
        let link = FileManager.default.temporaryDirectory.appending(path: "xcrew-tests-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        defer { try? FileManager.default.removeItem(at: link) }
        let project = Project(root: link)
        #expect(project.isApplePlatformProject)
        #expect(project.isGenerated)
        #expect(project.xcodeContainers == ["App.xcodeproj"])
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
        #expect(Project.temporary(containing: ["apps/ios/Project.swift", "apps/ios/Tuist"]).isTuistProject)
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

    @Test func anOrdinarySourceFileNamedLikeAManifestDoesntCount() {
        // Project.swift and Workspace.swift are common source-file names; below the root only Tuist's own files mark Tuist.
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write("struct Project {}", to: "App/Models/Project.swift")
        project.write("struct Workspace {}", to: "App/Workspace.swift")
        #expect(!project.isGenerated)
        #expect(!project.isTuistProject)
    }

    @Test func aTuistAppRootedByGitIsGenerated() {
        // Tuist finds its root by Tuist/, Tuist.swift or .git, so its manifests may stand below the root on their own.
        let project = Project.temporary(containing: [".git"])
        project.write("import ProjectDescription\n\nlet workspace = Workspace(name: \"App\", projects: [\"Projects/*\"])\n", to: "ios/Workspace.swift")
        project.write("import ProjectDescriptionHelpers\n\nlet project = Project.app(name: \"App\")\n", to: "ios/Projects/App/Project.swift")
        #expect(project.isGenerated)
        #expect(project.isTuistProject)
    }

    @Test func aProjectSwiftThatOnlyMentionsProjectDescriptionDoesntCount() {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write("// Unlike ProjectDescription's Project, this one is ours.\nlet note = \"import ProjectDescription\"\nstruct Project {}\n", to: "App/Project.swift")
        #expect(!project.isGenerated)
    }

    @Test func aNestedTuistAppOutsideGitIsStillGenerated() {
        // A miss here lets Claude edit a project the next generate overwrites.
        #expect(Project.temporary(containing: ["ios/Tuist.swift"]).isGenerated)
        #expect(Project.temporary(containing: ["apps/ios/Tuist"]).isTuistProject)
    }

    @Test func theHomeFolderIsNeverWalked() {
        let folder = Project.temporary(containing: [".git", "ios/Tuist.swift", "apps/ios/App.xcodeproj"])
        let home = Project(root: folder.root, home: folder.root)
        for reach in [ProjectLayout.Reach.repository, .anywhereButHome] {
            #expect(ProjectLayout.depth(of: home, reach: reach) == 0)
        }
        #expect(!home.isGenerated)
        #expect(!home.isApplePlatformProject)
    }

    @Test func aHomeFolderBelowTheRootIsntWalked() {
        // Claude Code started in /Users, or /, would otherwise list Desktop, Documents and Downloads.
        let folder = Project.temporary(containing: ["me/ios/Tuist.swift"])
        let project = Project(root: folder.root, home: folder.root.appending(path: "me"))
        #expect(!project.isGenerated)
    }

    @Test func dependenciesDontCount() {
        // A checked-out package that uses Tuist isn't this project being generated.
        #expect(!Project.temporary(containing: ["node_modules/x/Project.swift", ".build/checkouts/y/Tuist"]).isGenerated)
    }
}
