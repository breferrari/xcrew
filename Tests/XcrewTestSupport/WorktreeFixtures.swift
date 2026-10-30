import Foundation
import XcrewCore

extension FakeRunner {
    /// Answers git as it does in a linked worktree at `worktree`, at its repository's top level, whose main checkout is
    /// `main`.
    public mutating func linkWorktree(_ worktree: Project, to main: Project) {
        responses["git -C \(worktree.root.path) rev-parse --path-format=absolute --git-dir --git-common-dir --show-prefix"] = CommandResult(status: 0, stdout: "\(main.root.path)/.git/worktrees/wt\n\(main.root.path)/.git\n\n")
        responses["git -C \(worktree.root.path) worktree list --porcelain"] = CommandResult(status: 0, stdout: "worktree \(main.root.path)\nHEAD 0000000000000000000000000000000000000000\nbranch refs/heads/main\n\nworktree \(worktree.root.path)\nHEAD 0000000000000000000000000000000000000000\nbranch refs/heads/wt\n\n")
    }
}
