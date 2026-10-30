import Foundation

/// A new `xcrun mcpbridge` answers MCP's `initialize`, as Claude Code's own does when a session starts. Run only under a
/// Claude Code session: the bridge's caller is then an agent Xcode already permits, while from a terminal a first call
/// may ask Xcode to approve a new one. It starts a server, so only the full doctor runs it (docs/findings.md, *The Xcode
/// MCP after an Xcode switch*).
struct XcodeMCPHandshakeCheck: Check {
    let id = "xcode-mcp/handshake"
    let title = "A new Xcode MCP bridge answers"
    let startsAServer = true

    /// The bridge stops at the end of its input, before it answers: the input stays open until an answer comes, or for
    /// nine seconds, within the check's ten.
    static let command = ["/bin/sh", "-c", #"f=$(mktemp) && (cat; i=0; while [ "$i" -lt 90 ] && [ ! -s "$f" ]; do sleep 0.1; i=$((i + 1)); done) | xcrun mcpbridge > "$f"; cat "$f"; rm -f "$f""#]
    static let initialize = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"xcrew-doctor","version":"1"}}}"# + "\n"

    func run(_ context: CheckContext) async -> CheckResult {
        let list = await ProcessList.load(using: context.runner)
        guard list.ancestors(of: context.machine.processID).contains(where: { $0.program == "claude" }) else {
            return .skip("runs only from a Claude Code session, whose agent Xcode already permits")
        }
        let ran = await context.runner.run(Self.command, stdin: Data(Self.initialize.utf8), timeout: .seconds(10))
        guard let server = Self.server(in: ran.stdout) else {
            return .fail("a new Xcode MCP bridge (xcrun mcpbridge) didn't answer MCP's initialize: xcrun mcp-server status says whether the server is on, and /mcp → Reconnect restarts this session's")
        }
        return .pass("a new Xcode MCP bridge answers: \(server)")
    }

    /// The server's name and version from its answer to `initialize`; nil when no line is one.
    static func server(in output: String) -> String? {
        output.split(whereSeparator: \.isNewline).lazy.compactMap { line -> String? in
            guard let answer = ResultBundle.parse(String(line)) as? [String: Any], let result = answer["result"] as? [String: Any],
                  let info = result["serverInfo"] as? [String: Any], let name = info["name"] as? String
            else { return nil }
            return [name, info["version"] as? String].compactMap { $0 }.joined(separator: " ")
        }.first
    }
}
