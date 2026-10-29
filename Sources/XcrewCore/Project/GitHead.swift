import Foundation

/// What a project's git checkout has out: a branch, or a commit when HEAD is detached.
public enum GitHead: Sendable, Equatable {
    case branch(String)
    case commit(String)

    /// The project's HEAD, or nothing outside a git repository.
    public static func of(_ project: Project, using runner: any CommandRunning) async -> GitHead? {
        let root = project.root.path
        let branch = await runner.run("git", "-C", root, "symbolic-ref", "--short", "-q", "HEAD")
        if branch.succeeded, let name = firstLine(branch.stdout) { return .branch(name) }
        let commit = await runner.run("git", "-C", root, "rev-parse", "HEAD")
        return commit.succeeded ? firstLine(commit.stdout).map(GitHead.commit) : nil
    }

    static func firstLine(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline).first.map(String.init).flatMap { $0.isEmpty ? nil : $0 }
    }
}
