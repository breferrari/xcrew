import Foundation
import XcrewCore

extension FakeRunner {
    /// Answers git as it does in a linked worktree at `worktree`, at its repository's top level, whose main checkout is
    /// `main`.
    public mutating func linkWorktree(_ worktree: Project, to main: Project) {
        responses["git -C \(worktree.root.path) rev-parse --path-format=absolute --git-dir --git-common-dir --show-prefix"] = CommandResult(status: 0, stdout: "\(main.root.path)/.git/worktrees/wt\n\(main.root.path)/.git\n\n")
        responses["git -C \(worktree.root.path) rev-parse --path-format=absolute --git-common-dir"] = CommandResult(status: 0, stdout: "\(main.root.path)/.git\n")
        responses["git -C \(worktree.root.path) worktree list --porcelain"] = CommandResult(status: 0, stdout: "worktree \(main.root.path)\nHEAD 0000000000000000000000000000000000000000\nbranch refs/heads/main\n\nworktree \(worktree.root.path)\nHEAD 0000000000000000000000000000000000000000\nbranch refs/heads/wt\n\n")
    }

    /// `git worktree list --porcelain` for the main checkout `main` and its linked worktrees, the `prunable` ones' folders gone.
    public static func worktreeList(main: String, linked: [String], prunable: [String] = []) -> CommandResult {
        let blocks = ["worktree \(main)\nHEAD 1\nbranch refs/heads/main"]
            + linked.map { "worktree \($0)\nHEAD 2\nbranch refs/heads/linked" }
            + prunable.map { "worktree \($0)\nHEAD 3\ndetached\nprunable gitdir file points to non-existent location" }
        return CommandResult(status: 0, stdout: blocks.joined(separator: "\n\n") + "\n")
    }
}
