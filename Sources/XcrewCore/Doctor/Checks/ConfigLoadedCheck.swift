import Foundation

/// MobileBuildMCP reads its config only when its server starts (docs/findings.md, *MobileBuildMCP's profiles*). It
/// also writes the config itself when Claude saves session defaults, so the change compared is xcrew's own write,
/// the time of `.xcrew-managed`: setup, and mcs sync through setup. A hand edit needs a restart by hand.
/// The server compared is this session's, under the doctor's own Claude Code process; from a terminal, the
/// oldest serving this project under any Claude Code.
struct ConfigLoadedCheck: Check {
    let id = "mobilebuildmcp/config-loaded"
    let title = "MobileBuildMCP has the current config"

    func run(_ context: CheckContext) async -> CheckResult {
        guard let written = try? FileManager.default.attributesOfItem(atPath: context.project.managedMarker.path)[.modificationDate] as? Date else {
            return .skip("no config xcrew wrote")
        }
        let list = await context.processes.value()
        guard let (server, isSessions) = await list.mobileBuildMCPServer(serving: context.project, forSessionOf: context.machine.processID, using: context.runner) else {
            return .skip("MobileBuildMCP isn't running for this project")
        }
        guard written > Date(timeIntervalSinceNow: -TimeInterval(server.elapsed)) else {
            return .pass("loaded at its start")
        }
        return .warn(!isSessions
            ? "a MobileBuildMCP serving this project started before the config changed: restart its Claude Code session to load it"
            : "the config changed after this session's MobileBuildMCP started: restart Claude Code to load it")
    }
}
