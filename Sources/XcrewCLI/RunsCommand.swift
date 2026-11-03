import Foundation

import XcrewCore

/// The MobileBuildMCP runs going in the project's other worktrees, for the band's line under its own run.
struct RunsCommand: Command {
    let name = "runs"
    let usage = [
        "runs   (mod) the MobileBuildMCP runs going in the project's other worktrees, each with its tool and phase, as JSON",
    ]

    func run(_ invocation: Invocation) async throws -> Int32 {
        let runs = await OtherRuns.going(project: invocation.context.project, machine: invocation.context.machine, now: Date())
        invocation.print(String(decoding: try JSONEncoder.sorted.encode(runs), as: UTF8.self))
        return 0
    }
}
