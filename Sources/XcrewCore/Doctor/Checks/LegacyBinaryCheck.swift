import Foundation

/// A leftover XcodeBuildMCP install, from Homebrew or npm, can shadow the renamed server.
struct LegacyBinaryCheck: Check {
    let id = "mobilebuildmcp/no-legacy-binary"
    let title = "No old xcodebuildmcp on PATH"

    func run(_ context: CheckContext) async -> CheckResult {
        guard let old = context.runner.which("xcodebuildmcp") else { return .pass("none") }
        return .warn(Self.message(old))
    }

    /// The warning for the old binary at `old`: uninstalling it removes a tool of the person's, their call, said before the
    /// commands, which end the line.
    static func message(_ old: String) -> String {
        "old xcodebuildmcp at \(old). Uninstalling it removes a tool of the person's, so it's the person's to agree to: brew uninstall xcodebuildmcp, or npm uninstall -g xcodebuildmcp"
    }
}
