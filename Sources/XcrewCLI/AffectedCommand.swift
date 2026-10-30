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
        switch await GitChanges.since(invocation.arguments["base"], in: project, using: invocation.context.machine.runner) {
        case let .failure(failure):
            answer = Answer(base: "none", changed: [], selections: nil, runAll: failure.description)
        case let .success(change):
            let affected = AffectedTests.of(changed: change.files, in: project)
            let root = project.canonicalRoot + "/"
            answer = Answer(base: change.base, changed: change.files.map { $0.hasPrefix(root) ? String($0.dropFirst(root.count)) : $0 }, selections: affected.selections, runAll: affected.runAll)
        }
        invocation.print(String(decoding: try JSONEncoder.sorted.encode(answer), as: UTF8.self))
        return 0
    }
}
