import Foundation

/// MobileBuildMCP installed at `MobileBuildMCPStatus.minimum` or newer, as the session briefing also reads it.
struct MobileBuildMCPVersionCheck: Check {
    let id = "mobilebuildmcp/version"
    let title = "MobileBuildMCP \(MobileBuildMCPStatus.minimum) or newer"

    func run(_ context: CheckContext) async -> CheckResult {
        let status = await MobileBuildMCPStatus.assess(context.machine)
        switch status {
        case let .usable(version): return .pass("version \(version)")
        case .missing, .outdated, .unreadable:
            let problem = status.problem ?? ("not usable", "brew reinstall mobilebuildmcp")
            return .fail("\(problem.reason): \(problem.fix)")
        }
    }
}
