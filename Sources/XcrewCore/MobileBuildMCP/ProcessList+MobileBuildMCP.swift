import Foundation

extension ProcessList {
    /// The MobileBuildMCP servers Claude Code started for the session that runs `id`, and that session; with no
    /// session above `id`, as from a terminal, every Claude Code session's servers.
    func mobileBuildMCPServers(forSessionOf id: Int32) -> (session: Process?, servers: [Process]) {
        let session = ancestors(of: id).first { $0.program == "claude" }
        let servers = processes.filter { process in
            Self.isMobileBuildMCPServer(process) && ancestors(of: process.id).contains { $0.program == "claude" && (session == nil || $0.id == session?.id) }
        }
        return (session, servers)
    }

    /// The MobileBuildMCP server serving `project`: this session's, under the Claude Code process that runs `id`; from a
    /// terminal, the oldest under any Claude Code. Whether it's the session's, and nothing when none serves the project.
    func mobileBuildMCPServer(serving project: Project, forSessionOf id: Int32, using runner: any CommandRunning) async -> (server: Process, isSessions: Bool)? {
        let (session, candidates) = mobileBuildMCPServers(forSessionOf: id)
        let root = ProjectLayout.canonical(project.root)
        let folders = await Self.folders(of: candidates, using: runner)
        return candidates.filter { folders[$0.id] == root }.max { $0.elapsed < $1.elapsed }.map { ($0, session != nil) }
    }

    /// Each process's working folder, from one `lsof` for all of them: a `p` line names the process, its `n` line the folder.
    static func folders(of processes: [Process], using runner: any CommandRunning) async -> [Int32: String] {
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

    /// MobileBuildMCP's MCP server, as its Homebrew install runs it, whatever flags follow `mcp`.
    static func isMobileBuildMCPServer(_ process: Process) -> Bool {
        process.command.contains("/mobilebuildmcp/") && process.command.contains("build/cli.js mcp")
    }

    /// Whether `id` or a process above it is Xcode, by MobileBuildMCP 2.7.1's test (`utils/xcode-process.js`): a program
    /// named `Xcode`, or a command naming `Contents/MacOS/Xcode` or `com.apple.dt.Xcode`.
    ///
    /// The parser splits `pid ppid comm args` on spaces: the name is `comm`'s first word, the command all after it. `ps`
    /// cuts `comm` to 16 characters when a column follows it.
    func runsUnderXcode(_ id: Int32) -> Bool {
        let chain = processes.filter { $0.id == id } + ancestors(of: id)
        return chain.contains { process in
            let comm = process.programPath.prefix(16).split(whereSeparator: \.isWhitespace)
            let name = comm.first.map(String.init) ?? ""
            let command = (comm.dropFirst() + process.command.split(whereSeparator: \.isWhitespace)).joined(separator: " ")
            return name == "Xcode" || command.contains("Contents/MacOS/Xcode") || command.contains("com.apple.dt.Xcode")
        }
    }
}
