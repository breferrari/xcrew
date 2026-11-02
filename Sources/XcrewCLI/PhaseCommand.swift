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
        /// The scheme the log's invocation names, which the mod keys the run by.
        let scheme: String?
        /// The log's xcodebuild verdict, once printed: a run moved to the background is followed until it.
        var outcome: Bool?
        /// True when the log has gone unwritten as long as `OtherRuns.quietFor`, or hasn't appeared that long after the
        /// call began: its run stopped without a verdict, or never wrote one.
        var quiet: Bool?
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
        let kind: Report.Kind = tool.hasPrefix("test") ? .test : .build
        let outcome = log.flatMap { RunLog.outcome(of: RunLog.tail(ofLogAt: $0), kind: kind) }
        let written = log.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        let began = Date(timeIntervalSince1970: since / 1000)
        let quiet = outcome == nil && (written.map { Date().timeIntervalSince($0) >= OtherRuns.quietFor } ?? (log == nil && Date().timeIntervalSince(began) >= OtherRuns.quietFor))
        let encoded = try JSONEncoder.sorted.encode(Answer(log: log?.path, phase: phase, scheme: log.flatMap(RunLog.scheme(ofLogAt:)), outcome: outcome, quiet: quiet ? true : nil))
        invocation.print(String(decoding: encoded, as: UTF8.self))
        return 0
    }
}
