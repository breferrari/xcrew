import Foundation
import XcrewCore

/// The tests a change can break, as JSON, for the mod's `affected` tool: the base it compared against, the files that
/// changed, and either the test targets to select or why everything must run. The change is everything since the merge
/// base with the remote's default branch, uncommitted and untracked files included; with no remote, the working tree.
struct AffectedCommand: Command {
    let name = "affected"
    let valuedOptions: Set<String> = ["base"]
    let usage = ["affected [--base <ref>]   the tests a change can break, as JSON: since the merge base with <ref>, or with the remote's default branch"]

    struct Answer: Codable, Equatable {
        let base: String
        let changed: [String]
        let selections: [String]?
        let runAll: String?
    }

    func run(_ invocation: Invocation) async throws -> Int32 {
        let project = invocation.context.project
        let answer: Answer
        switch await Self.changes(in: project, base: invocation.arguments["base"], runner: invocation.context.machine.runner) {
        case let .failure(reason):
            answer = Answer(base: "none", changed: [], selections: nil, runAll: reason.description)
        case let .success((base, files)):
            let affected = AffectedTests.of(changed: files, in: project)
            let root = project.canonicalRoot + "/"
            answer = Answer(base: base, changed: files.map { $0.hasPrefix(root) ? String($0.dropFirst(root.count)) : $0 }, selections: affected.selections, runAll: affected.runAll)
        }
        invocation.print(String(decoding: try JSONEncoder.sorted.encode(answer), as: UTF8.self))
        return 0
    }

    struct GitError: Error, CustomStringConvertible {
        let description: String
    }

    /// The base compared against, said in words, and the changed files as absolute paths.
    static func changes(in project: Project, base: String?, runner: any CommandRunning) async -> Result<(String, [String]), GitError> {
        let root = project.root.path
        let git = { (arguments: [String]) in await runner.run(["git", "-C", root] + arguments, stdin: nil, timeout: .seconds(30)) }
        let top = await git(["rev-parse", "--show-toplevel"])
        guard top.succeeded, let topLevel = lines(top.stdout).first else { return .failure(GitError(description: "this isn't a git repository, so the change can't be told apart")) }
        var reference = base
        if reference == nil {
            let remoteDefault = await git(["rev-parse", "--abbrev-ref", "origin/HEAD"])
            reference = remoteDefault.succeeded ? lines(remoteDefault.stdout).first : nil
        }
        let described: String
        let diff: CommandResult
        if let reference {
            let mergeBase = await git(["merge-base", "HEAD", reference])
            guard mergeBase.succeeded, let commit = lines(mergeBase.stdout).first else { return .failure(GitError(description: "git found no merge base with \(reference)")) }
            described = "\(reference), from \(commit.prefix(12))"
            diff = await git(["diff", "--name-only", commit])
        } else {
            described = "the working tree, since there is no remote default branch"
            diff = await git(["diff", "--name-only", "HEAD"])
        }
        let untracked = await git(["ls-files", "--others", "--exclude-standard", "--full-name"])
        guard diff.succeeded, untracked.succeeded else { return .failure(GitError(description: "git couldn't list the changed files")) }
        let files = (lines(diff.stdout) + lines(untracked.stdout)).map { URL(fileURLWithPath: ProjectLayout.canonicalPath(topLevel)).appending(path: $0).path }
        return .success((described, files.reduce(into: []) { unique, file in if !unique.contains(file) { unique.append(file) } }))
    }

    static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
    }
}
