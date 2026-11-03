import Foundation

import XcrewCore

/// The MobileBuildMCP runs going in the project's other worktrees, for the band's line under its own run; or, with
/// `--overlapped`, the worktrees whose run went while this checkout's did, for the mod to keep it out of the usual time.
struct RunsCommand: Command {
    let name = "runs"
    let valuedOptions: Set<String> = ["since", "until"]
    let flags: Set<String> = ["overlapped"]
    let usage = [
        "runs   (mod) the MobileBuildMCP runs going in the project's other worktrees, each with its tool and phase, as JSON",
        "runs --overlapped --since MS --until MS   (mod) the other worktrees whose xcodebuild run went between those times, in milliseconds, as JSON",
    ]

    func run(_ invocation: Invocation) async throws -> Int32 {
        if invocation.arguments.has("overlapped") {
            guard let since = invocation.arguments["since"].flatMap(Double.init), let until = invocation.arguments["until"].flatMap(Double.init) else {
                throw UsageError(description: "runs --overlapped needs --since and --until, in milliseconds")
            }
            let names = await OtherRuns.overlapped(project: invocation.context.project, machine: invocation.context.machine, from: Date(timeIntervalSince1970: since / 1000), to: Date(timeIntervalSince1970: until / 1000))
            invocation.print(String(decoding: try JSONEncoder.sorted.encode(names), as: UTF8.self))
            return 0
        }
        let runs = await OtherRuns.going(project: invocation.context.project, machine: invocation.context.machine)
        invocation.print(String(decoding: try JSONEncoder.sorted.encode(runs), as: UTF8.self))
        return 0
    }
}
