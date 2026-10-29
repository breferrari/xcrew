import Foundation

import XcrewCore

/// What kind of project this is, as JSON: whether a generator writes it, for the mod's `XcodeWrite` guard, and
/// with `--setup` the container setup would build, for the setup skill. The guard runs it on every call, so only
/// the skill pays for the container's search.
struct ProjectCommand: Command {
    let name = "project"
    let flags: Set<String> = ["setup"]
    let usage = [
        "project [--setup]   whether a generator writes this project, as JSON; --setup adds the container setup would use",
    ]

    struct Answer: Codable, Equatable {
        let isGenerated: Bool
        var container: String?
        var containerProblem: String?
    }

    func run(_ invocation: Invocation) async throws -> Int32 {
        var answer = Answer(isGenerated: invocation.context.project.isGenerated)
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
