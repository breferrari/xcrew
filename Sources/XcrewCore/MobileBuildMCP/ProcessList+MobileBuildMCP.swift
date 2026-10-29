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

    /// MobileBuildMCP's MCP server, as its Homebrew install runs it, whatever flags follow `mcp`.
    static func isMobileBuildMCPServer(_ process: Process) -> Bool {
        process.command.contains("/mobilebuildmcp/") && process.command.contains("build/cli.js mcp")
    }
}
