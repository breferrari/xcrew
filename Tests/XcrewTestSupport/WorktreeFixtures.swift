import Foundation
import XcrewCore

extension FakeRunner {
    /// Answers git as it does in a linked worktree at `worktree` whose main checkout is `main`.
    public mutating func linkWorktree(_ worktree: Project, to main: Project) {
        responses["git -C \(worktree.root.path) rev-parse --path-format=absolute --git-dir --git-common-dir"] = CommandResult(status: 0, stdout: "\(main.root.path)/.git/worktrees/wt\n\(main.root.path)/.git\n")
    }
}
