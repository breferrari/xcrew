import Foundation

/// This session's Xcode MCP, `xcrun mcpbridge` under the session's Claude Code, runs the bridge of the Xcode selected
/// when it started. After `xcode-select` chooses another, its calls fail with "Connection closed" until /mcp restarts
/// it (docs/findings.md, *The Xcode MCP after an Xcode switch*). Read from `ps`, so it runs with the line above the prompt.
struct XcodeMCPBridgeCheck: Check {
    let id = "xcode-mcp/session-bridge"
    let title = "This session's Xcode MCP uses the selected Xcode"

    func run(_ context: CheckContext) async -> CheckResult {
        let list = await ProcessList.load(using: context.runner)
        guard let session = list.ancestors(of: context.machine.processID).first(where: { $0.program == "claude" }),
              let bridge = list.processes.first(where: { $0.program == "mcpbridge" && list.ancestors(of: $0.id).contains { $0.id == session.id } }),
              let app = Xcodes.app(holding: bridge.programPath)
        else { return .skip("this session runs no Xcode MCP") }
        let xcodes = await context.xcodes.value()
        guard let selected = xcodes.selected else { return .skip("no Xcode is selected here") }
        let label = Xcodes.install(at: app)?.label ?? app.lastPathComponent
        guard ProjectLayout.canonical(app) == ProjectLayout.canonicalPath(selected.path) else {
            return .fail("this session's Xcode MCP runs \(label)'s bridge, but \(selected.label) is selected now, so its calls fail with \"Connection closed\": /mcp → Reconnect restarts it with \(selected.label)")
        }
        return .pass("this session's Xcode MCP runs \(label)'s bridge, the selected one")
    }
}
