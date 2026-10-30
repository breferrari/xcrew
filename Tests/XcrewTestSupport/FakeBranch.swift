import Foundation
import XcrewCore

extension FakeRunner {
    /// The merge base every fake branch shares.
    public static let base = "0123456789abcdef0123456789abcdef01234567"

    /// git's answers about a branch of the repository at `root`: off `origin/main` from `base`, or, without a remote's
    /// default branch, no base at all. It changed `files`, relative to `root`, and `diff` is the `-U0` diff of
    /// `diffed`, absolute as the file system spells them.
    public static func branch(at root: URL, changed files: [String], diffed: [String], diff: String, remote: Bool = true) -> [String: CommandResult] {
        let git = { (arguments: String) in "git -C \(root.path) \(arguments)" }
        var responses: [String: CommandResult] = [
            git("rev-parse --show-toplevel"): .init(status: 0, stdout: "\(root.path)\n"),
            git("diff --name-only --no-renames --no-relative -z \(base)"): .init(status: 0, stdout: files.map { "\($0)\u{0}" }.joined()),
            git("ls-files -z --others --exclude-standard --full-name"): .init(status: 0),
            git("-c core.quotePath=false diff -U0 --no-color --no-renames --no-relative --no-prefix \(base) -- \(diffed.joined(separator: " "))"): .init(status: 0, stdout: diff),
        ]
        if remote {
            responses[git("rev-parse --abbrev-ref origin/HEAD")] = .init(status: 0, stdout: "origin/main\n")
            responses[git("merge-base HEAD origin/main")] = .init(status: 0, stdout: "\(base)\n")
        } else {
            responses[git("rev-parse --abbrev-ref origin/HEAD")] = .init(status: 128)
            responses[git("remote")] = .init(status: 0, stdout: "upstream\n")
        }
        return responses
    }
}
