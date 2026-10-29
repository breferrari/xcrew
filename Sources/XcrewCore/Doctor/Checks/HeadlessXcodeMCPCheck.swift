import Foundation

/// Xcode's MCP server runs without the Xcode window once enabled for the Mac.
struct HeadlessXcodeMCPCheck: Check {
    let id = "xcode-mcp/headless-enabled"
    let title = "Headless Xcode MCP enabled"

    func run(_ context: CheckContext) async -> CheckResult {
        let status = await context.xcodeMCPStatus.value()
        guard status.succeeded else { return .fail("xcrun mcp-server unavailable (needs Xcode 27 or later)") }
        guard status.stdout.contains("Permission: enabled") else {
            return .fail("headless Xcode MCP is off: sudo xcrun mcp-server enable")
        }
        return .pass("enabled")
    }
}
