import Foundation

/// 2.7.1 renamed XcodeBuildMCP's binary, environment variables and config folder, with no
/// fallback to the old names; everything xcrew writes assumes the new ones.
struct MobileBuildMCPVersionCheck: Check {
    static let minimum = Version("2.7.1")
    let id = "mobilebuildmcp/version"
    let title = "MobileBuildMCP \(minimum) or newer"

    func run(_ context: CheckContext) async -> CheckResult {
        guard context.machine.hasMobileBuildMCP else {
            return .fail("not installed: brew install getsentry/xcodebuildmcp/mobilebuildmcp")
        }
        let version = Version(await context.runner.run("mobilebuildmcp", "--version").stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        guard version >= Self.minimum else {
            return .fail("version \(version) is older than \(Self.minimum): brew upgrade mobilebuildmcp")
        }
        return .pass("version \(version)")
    }
}
