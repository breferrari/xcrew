import Foundation

/// Xcode's MCP server runs without the Xcode window once enabled for the Mac.
struct HeadlessXcodeMCPCheck: Check {
    let id = "xcode-mcp/headless-enabled"
    let title = "Headless Xcode MCP enabled"
    static let introduced = 27

    /// Why `xcrun mcp-server` can't answer on this Mac by choice rather than fault, as the line both Xcode MCP checks
    /// show: every installed Xcode predates it, or the selected one does while a newer one is installed, which may be
    /// deliberate. Nil when neither holds, or an Xcode's version is unknown, since it could be new enough.
    static func unavailable(_ context: CheckContext) async -> CheckResult? {
        let xcodes = await context.xcodes.value()
        let known = xcodes.installed.compactMap { install in Version.major(of: install.version).map { (install, $0) } }
        guard !known.isEmpty, known.count == xcodes.installed.count else { return nil }
        let newer = known.filter { $0.1 >= introduced }.map(\.0).max { Version($0.version) < Version($1.version) }
        guard let newer else { return .skip("available with Xcode \(introduced) or later") }
        guard let selected = xcodes.selected, let major = Version.major(of: selected.version), major < introduced else { return nil }
        return .skip("\(newer.label) is installed: `sudo xcode-select -s \(newer.path)` turns on headless Xcode MCP")
    }

    /// Whether `xcrun mcp-server status` says the headless server is on.
    static func isEnabled(_ status: CommandResult) -> Bool {
        status.succeeded && status.stdout.contains("Permission: enabled")
    }

    func run(_ context: CheckContext) async -> CheckResult {
        let status = await context.xcodeMCPStatus.value()
        guard status.succeeded else {
            return await Self.unavailable(context) ?? .fail("xcrun mcp-server unavailable (needs Xcode \(Self.introduced) or later)")
        }
        guard Self.isEnabled(status) else {
            return .fail("headless Xcode MCP is off: sudo xcrun mcp-server enable")
        }
        return .pass("enabled")
    }
}
