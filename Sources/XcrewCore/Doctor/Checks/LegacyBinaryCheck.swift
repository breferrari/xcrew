import Foundation

/// A leftover XcodeBuildMCP install, from Homebrew or npm, can shadow the renamed server.
struct LegacyBinaryCheck: Check {
    let id = "mobilebuildmcp/no-legacy-binary"
    let title = "No old xcodebuildmcp on PATH"

    func run(_ context: CheckContext) async -> CheckResult {
        guard let old = context.runner.which("xcodebuildmcp") else { return .pass("none") }
        return .warn("old xcodebuildmcp at \(old): brew uninstall xcodebuildmcp, or npm uninstall -g xcodebuildmcp")
    }
}
