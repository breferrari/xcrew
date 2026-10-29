import Foundation

/// Whether MobileBuildMCP can serve builds and tests on this Mac, as the doctor and the session briefing both read it.
enum MobileBuildMCPStatus: Sendable, Equatable {
    case usable(version: String)
    case missing
    /// Older than the minimum; an empty version is one that couldn't be read.
    case outdated(version: String)

    /// The version comes from the doctor's cache while the binary is unchanged, so this runs no process then.
    static func assess(_ context: CheckContext) async -> MobileBuildMCPStatus {
        guard context.machine.hasMobileBuildMCP else { return .missing }
        let version = await MobileBuildMCPVersionCheck.version(context)
        return Version(version) >= MobileBuildMCPVersionCheck.minimum ? .usable(version: version) : .outdated(version: version)
    }

    /// Why MobileBuildMCP can't serve, and the command that fixes it; nil when it can.
    var problem: (reason: String, fix: String)? {
        switch self {
        case .usable: nil
        case .missing: ("not installed", "brew install getsentry/xcodebuildmcp/mobilebuildmcp")
        case let .outdated(version):
            (version.isEmpty ? "its version couldn't be read" : "version \(version) is older than \(MobileBuildMCPVersionCheck.minimum)", "brew upgrade mobilebuildmcp")
        }
    }
}
