import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// A linked git worktree, as `git worktree add` or Claude Code's `--worktree` makes one, and the config it can take
/// from its main checkout.
@Suite struct WorktreeTests {
    /// Runs git with nothing from this Mac's own config that could stop it: no signing, no hooks.
    static func git(_ arguments: [String], in folder: URL) async -> Bool {
        let hermetic = ["-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "-c", "user.name=t", "-c", "user.email=t@t"]
        return await SystemCommandRunner().run(["git", "-C", folder.path] + hermetic + arguments, stdin: nil, timeout: .seconds(30)).succeeded
    }

    /// A temporary folder holding a real repository, `main`, with one commit and an `ios` subfolder, and a linked
    /// worktree of it, `wt`; removed after `body`. git's own answers, not a fake's.
    static func repository<T>(_ body: (_ main: URL, _ worktree: URL) async throws -> T) async throws -> T {
        let folder = Project.temporary().root
        defer { try? FileManager.default.removeItem(at: folder) }
        let main = folder.appending(path: "main")
        try FileManager.default.createDirectory(at: main.appending(path: "ios"), withIntermediateDirectories: true)
        try Data().write(to: main.appending(path: "ios/README"))
        #expect(await git(["init", "-q"], in: main))
        #expect(await git(["add", "."], in: main))
        #expect(await git(["commit", "-q", "-m", "init"], in: main))
        #expect(await git(["worktree", "add", "-q", folder.appending(path: "wt").path], in: main))
        return try await body(main, folder.appending(path: "wt"))
    }

    @Test func aWorktreeKnowsItsMainCheckout() async throws {
        try await Self.repository { main, worktree in
            let found = await Worktree.mainCheckout(of: Project(root: worktree), using: SystemCommandRunner())
            #expect(found.map(ProjectLayout.canonical) == ProjectLayout.canonical(main))
            #expect(await Worktree.mainCheckout(of: Project(root: main), using: SystemCommandRunner()) == nil)
        }
        #expect(await Worktree.mainCheckout(of: Project.temporary(), using: SystemCommandRunner()) == nil)
    }

    /// A project a folder down in its repository, as an app in a monorepo: its main checkout is the same folder there.
    @Test func aProjectInASubfolderFindsTheSameSubfolder() async throws {
        try await Self.repository { main, worktree in
            let found = await Worktree.mainCheckout(of: Project(root: worktree.appending(path: "ios")), using: SystemCommandRunner())
            #expect(found.map(ProjectLayout.canonical) == ProjectLayout.canonical(main.appending(path: "ios")))
        }
    }

    /// A bare repository kept in `.git`, with its worktrees beside it, has no main checkout to take a config from.
    @Test func aBareRepositorysWorktreeHasNone() async throws {
        try await Self.repository { main, _ in
            let project = main.deletingLastPathComponent().appending(path: "bare")
            #expect(await Self.git(["clone", "-q", "--bare", main.path, project.appending(path: ".git").path], in: main))
            #expect(await Self.git(["worktree", "add", "-q", project.appending(path: "feature").path], in: project.appending(path: ".git")))
            #expect(await Worktree.mainCheckout(of: Project(root: project.appending(path: "feature")), using: SystemCommandRunner()) == nil)
        }
    }

    /// The main checkout's config as the worktree takes it: a path inside the main checkout is written from the root,
    /// so it reaches the worktree's own; a DerivedData outside it is left out, so the two don't build into one; a path
    /// already written from the root stays as it is. A comment after a value doesn't hide it.
    @Test func theConfigTakesPathsToTheWorktree() {
        let main = URL(fileURLWithPath: "/work/App")
        let yaml = """
            schemaVersion: 1
            sessionDefaultsProfiles:
              unit:
                projectPath: '/work/App/App.xcodeproj'
                scheme: 'App'
                derivedDataPath: '/Users/someone/DerivedData/App' # shared
              app:
                workspacePath: "/work/App/App.xcworkspace"
                derivedDataPath: /work/App/DerivedData
              ui:
                projectPath: 'App.xcodeproj'
            activeSessionDefaultsProfile: unit

            """
        let (taken, leftOut) = Worktree.config(from: yaml, main: main)
        #expect(taken == """
            schemaVersion: 1
            sessionDefaultsProfiles:
              unit:
                projectPath: './App.xcodeproj'
                scheme: 'App'
              app:
                workspacePath: './App.xcworkspace'
                derivedDataPath: './DerivedData'
              ui:
                projectPath: 'App.xcodeproj'
            activeSessionDefaultsProfile: unit

            """)
        #expect(leftOut.map(\.key) == ["derivedDataPath"])
        #expect(leftOut.map(\.path) == ["/Users/someone/DerivedData/App"])
    }

    /// A main checkout whose config names no scheme, as one MobileBuildMCP wrote itself, has nothing to copy.
    @Test func aMainConfigWithoutASchemeIsNotOffered() async {
        let main = Project.temporary(containing: ["App.xcodeproj"])
        main.write("schemaVersion: 1\nsessionDefaults:\n  projectPath: ./App.xcodeproj\n", to: ".mobilebuildmcp/config.yaml")
        let worktree = Project.temporary(containing: ["App.xcodeproj"])
        var runner = FakeRunner()
        runner.linkWorktree(worktree, to: main)
        #expect(await Worktree.takesMainConfig(worktree, using: runner) == false)
        main.write("schemaVersion: 1\nsessionDefaultsProfiles:\n  unit:\n    projectPath: 'App.xcodeproj'\n    scheme: 'App'\nactiveSessionDefaultsProfile: unit\n", to: ".mobilebuildmcp/config.yaml")
        #expect(await Worktree.takesMainConfig(worktree, using: runner))
    }
}
