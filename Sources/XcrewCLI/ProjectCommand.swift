import Foundation

import XcrewCore

/// What kind of project this is, as JSON: whether a generator writes it, for the mod's `XcodeWrite` guard, and
/// with `--setup` the container setup would build, for the setup skill. The guard runs it on every call, so only
/// the skill pays for the container's search. The mod asks with `--manifest` after each edit to a manifest's name.
struct ProjectCommand: Command {
    let name = "project"
    let flags: Set<String> = ["setup"]
    let valuedOptions: Set<String> = ["manifest"]
    let usage = [
        "project [--setup] [--manifest <file>]   whether a generator writes this project, as JSON; --setup adds the container setup would use, and --manifest the command that regenerates the project after an edit to <file>, when the generator reads it",
    ]

    struct Answer: Codable, Equatable {
        let isGenerated: Bool
        var container: String?
        var containerProblem: String?
        /// The command to run before the next build, when the file `--manifest` names is one the generator reads.
        var generate: String?
        /// The app that command regenerates, as the path of its manifests' folder from the root: empty for the root.
        var app: String?
    }

    func run(_ invocation: Invocation) async throws -> Int32 {
        let project = invocation.context.project
        let layout = project.layout(.anywhereButHome)
        let nearest = layout.generator
        var answer = Answer(isGenerated: nearest != nil)
        if let manifest = invocation.arguments["manifest"], let nearest {
            let file = manifest.hasPrefix("/") ? URL(fileURLWithPath: manifest) : project.root.appending(path: manifest)
            let found = layout.command(after: file, nearest: nearest)
            (answer.generate, answer.app) = (found?.command, found?.manifests.path)
        }
        if invocation.arguments.has("setup") {
            do {
                answer.container = try SetupCommand.container(in: invocation.context)
            } catch {
                answer.containerProblem = String(describing: error)
            }
        }
        invocation.print(String(decoding: try JSONEncoder.sorted.encode(answer), as: UTF8.self))
        return 0
    }
}
