import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// A linked git worktree, as `git worktree add` or Claude Code's `--worktree` makes one, and the config it can take
/// from its main checkout.
@Suite struct WorktreeTests {
    /// A real repository with one commit and a linked worktree beside it; git's own answers, not a fake's.
    static func repository() async throws -> (main: Project, worktree: Project) {
        let main = Project.temporary()
        let git = SystemCommandRunner()
        for argv in [["init", "-q"], ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init"]] {
            #expect(await git.run(["git", "-C", main.root.path] + argv, stdin: nil, timeout: .seconds(30)).succeeded)
        }
        let worktree = main.root.deletingLastPathComponent().appending(path: main.root.lastPathComponent + "-wt")
        #expect(await git.run(["git", "-C", main.root.path, "worktree", "add", "-q", worktree.path], stdin: nil, timeout: .seconds(30)).succeeded)
        return (main, Project(root: worktree))
    }

    @Test func aWorktreeKnowsItsMainCheckout() async throws {
        let (main, worktree) = try await Self.repository()
        let found = await Worktree.mainCheckout(of: worktree, using: SystemCommandRunner())
        #expect(found.map(ProjectLayout.canonical) == ProjectLayout.canonical(main.root))
        #expect(await Worktree.mainCheckout(of: main, using: SystemCommandRunner()) == nil)
        #expect(await Worktree.mainCheckout(of: Project.temporary(), using: SystemCommandRunner()) == nil)
    }

    /// The main checkout's config, as the worktree takes it: paths written from the root work there as they are; an
    /// absolute path, outside the checkout, is left out, so the worktree's builds don't share the main checkout's
    /// DerivedData.
    @Test func theConfigLeavesOutAbsolutePaths() {
        let main = """
            schemaVersion: 1
            sessionDefaultsProfiles:
              unit:
                projectPath: "App.xcodeproj"
                scheme: "App"
                derivedDataPath: "/Users/someone/DerivedData/App"
              app:
                projectPath: "App.xcodeproj"
                derivedDataPath: ./DerivedData
            activeSessionDefaultsProfile: unit

            """
        let (yaml, leftOut) = Worktree.config(from: main)
        #expect(yaml == main.replacingOccurrences(of: "    derivedDataPath: \"/Users/someone/DerivedData/App\"\n", with: ""))
        #expect(leftOut.map(\.key) == ["derivedDataPath"])
        #expect(leftOut.map(\.path) == ["/Users/someone/DerivedData/App"])
    }
}
