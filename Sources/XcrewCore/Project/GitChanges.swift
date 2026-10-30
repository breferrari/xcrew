import Foundation

/// What a branch changed: everything since its merge base with a base branch, uncommitted and untracked files included.
/// A wrong base hides changes, and hidden changes are skipped tests, so a base that can't be found is a failure, not an
/// empty change.
public enum GitChanges {
    public struct Change: Sendable, Equatable {
        /// The base, in words: `origin/main, from 0123456789ab`.
        public let base: String
        /// The changed files, absolute, as the file system spells the repository.
        public let files: [String]
    }

    public struct Failure: Error, CustomStringConvertible, Sendable {
        public let description: String
    }

    /// The remote branches tried, in order, when `origin/HEAD` isn't set: a clone sets it, a push doesn't.
    static let defaultBranches = ["origin/main", "origin/master"]

    public static func since(_ base: String?, in project: Project, using runner: any CommandRunning) async -> Result<Change, Failure> {
        let git = { (arguments: [String]) in await runner.run(["git", "-C", project.root.path] + arguments, stdin: nil, timeout: .seconds(30)) }
        let top = await git(["rev-parse", "--show-toplevel"])
        guard top.succeeded, let topLevel = GitHead.firstLine(top.stdout) else { return .failure(Failure(description: "this isn't a git repository, so the change can't be told apart")) }
        var reference = base
        if reference == nil {
            let remoteHead = await git(["rev-parse", "--abbrev-ref", "origin/HEAD"])
            reference = remoteHead.succeeded ? GitHead.firstLine(remoteHead.stdout) : nil
        }
        if reference == nil {
            for candidate in defaultBranches where await git(["rev-parse", "--verify", "--quiet", candidate]).succeeded {
                reference = candidate
                break
            }
        }
        if reference == nil, GitHead.firstLine(await git(["remote"]).stdout) != nil {
            return .failure(Failure(description: "the remote's default branch isn't known here (origin/HEAD, origin/main or origin/master), so the branch's own commits can't be told apart: `git remote set-head origin --auto` sets it"))
        }
        let described: String
        let since: String
        if let reference {
            let mergeBase = await git(["merge-base", "HEAD", reference])
            guard mergeBase.succeeded, let commit = GitHead.firstLine(mergeBase.stdout) else { return .failure(Failure(description: "git found no merge base with \(reference)")) }
            (described, since) = ("\(reference), from \(commit.prefix(12))", commit)
        } else {
            (described, since) = ("the working tree, since there is no remote", "HEAD")
        }
        // Both sides of a rename, and every name as written: NUL-separated, never quoted or made relative.
        let diff = await git(["diff", "--name-only", "--no-renames", "--no-relative", "-z", since])
        let untracked = await git(["ls-files", "-z", "--others", "--exclude-standard", "--full-name"])
        guard diff.succeeded, untracked.succeeded else { return .failure(Failure(description: "git couldn't list the changed files")) }
        let topPath = ProjectLayout.canonicalPath(topLevel)
        var seen = Set<String>()
        let files = (diff.stdout + untracked.stdout).split(separator: "\0").map { "\(topPath)/\($0)" }.filter { seen.insert($0).inserted }
        return .success(Change(base: described, files: files))
    }
}
