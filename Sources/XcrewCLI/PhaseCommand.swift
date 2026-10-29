import Foundation

import XcrewCore

/// What a running MobileBuildMCP call is doing, for the band: its log, once it appears, and the phase
/// read from it. The mod asks once a second while a build or test runs.
struct PhaseCommand: Command {
    let name = "phase"
    let valuedOptions: Set<String> = ["tool", "since", "expected", "log"]
    let usage = [
        "phase --tool T --since MS [--expected N] [--log PATH]   (mod) the running call's log and phase, as JSON",
    ]

    struct Answer: Codable, Equatable {
        let log: String?
        let phase: String?
    }

    func run(_ invocation: Invocation) async throws -> Int32 {
        guard let tool = invocation.arguments["tool"] else { throw UsageError(description: "phase needs --tool") }
        guard let since = invocation.arguments["since"].flatMap(Double.init) else { throw UsageError(description: "phase needs --since, in milliseconds") }
        let context = invocation.context
        let log: URL?
        if let given = invocation.arguments["log"] {
            log = URL(fileURLWithPath: given)
        } else {
            log = await RunLog.find(tool: tool, since: Date(timeIntervalSince1970: since / 1000), project: context.project.root, machine: context.machine)
        }
        let phase = log.flatMap { RunLog.phase(ofLogAt: $0, expectedTests: invocation.arguments["expected"].flatMap(Int.init)) }
        let encoded = try JSONEncoder.sorted.encode(Answer(log: log?.path, phase: phase))
        invocation.print(String(decoding: encoded, as: UTF8.self))
        return 0
    }
}
