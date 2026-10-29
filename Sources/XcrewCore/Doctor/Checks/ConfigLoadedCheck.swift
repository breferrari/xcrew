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
        let list = await ProcessList.load(using: context.runner)
        let session = list.ancestors(of: context.machine.processID).first { $0.program == "claude" }
        let candidates = list.processes.filter { process in
            Self.isServer(process) && list.ancestors(of: process.id).contains { $0.program == "claude" && (session == nil || $0.id == session?.id) }
        }
        let root = ProjectLayout.canonical(context.project.root)
        let folders = await Self.folders(of: candidates, using: context.runner)
        guard let server = candidates.filter({ folders[$0.id] == root }).max(by: { $0.elapsed < $1.elapsed }) else {
            return .skip("MobileBuildMCP isn't running for this project")
        }
        guard written > Date(timeIntervalSinceNow: -TimeInterval(server.elapsed)) else {
            return .pass("loaded at its start")
        }
        return .warn(session == nil
            ? "a MobileBuildMCP serving this project started before the config changed: restart its Claude Code session to load it"
            : "the config changed after this session's MobileBuildMCP started: restart Claude Code to load it")
    }

    static func isServer(_ process: ProcessList.Process) -> Bool {
        process.command.contains("/mobilebuildmcp/") && process.command.hasSuffix("build/cli.js mcp")
    }

    /// Each process's working folder, from one `lsof` for all of them: a `p` line names the process, its `n` line the folder.
    static func folders(of processes: [ProcessList.Process], using runner: any CommandRunning) async -> [Int32: String] {
        guard !processes.isEmpty else { return [:] }
        let ids = processes.map { String($0.id) }.joined(separator: ",")
        var folders: [Int32: String] = [:]
        var current: Int32?
        for line in await runner.run("lsof", "-a", "-p", ids, "-d", "cwd", "-Fn").stdout.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("p") { current = Int32(line.dropFirst()) }
            if line.hasPrefix("n"), let id = current { folders[id] = ProjectLayout.canonical(URL(fileURLWithPath: String(line.dropFirst()))) }
        }
        return folders
    }
}
