import Foundation

/// Xcode asks once per agent; until then every Xcode MCP call fails with "not approved".
struct ClaudeApprovedCheck: Check {
    static let agentIdentifier = "com.anthropic.claude-code"
    let id = "xcode-mcp/claude-approved"
    let title = "Claude Code approved in Xcode"

    func run(_ context: CheckContext) async -> CheckResult {
        let status = await context.xcodeMCPStatus.value()
        guard status.succeeded else { return .skip("xcrun mcp-server unavailable") }
        guard status.stdout.contains(Self.agentIdentifier) else {
            return .warn("not approved yet: have Claude call XcodeOpenWorkspace, then allow it in Xcode's dialog")
        }
        return .pass("approved")
    }
}
