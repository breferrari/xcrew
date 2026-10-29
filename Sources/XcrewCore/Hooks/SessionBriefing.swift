import Foundation

/// What a Claude Code session in an Apple-platform project starts with: the routing rules, then
/// whatever this Mac or project still lacks. Silent in any other project.
public struct SessionBriefing: Sendable {
    let project: Project
    let machine: Machine

    public init(project: Project, machine: Machine) {
        self.project = project
        self.machine = machine
    }

    public func text(routing: String) -> String? {
        guard project.isApplePlatformProject else { return nil }
        let lines = [routing.trimmingCharacters(in: .whitespacesAndNewlines)] + gaps().map { "- **xcrew:** \($0)" }
        return lines.joined(separator: "\n")
    }

    /// Fast checks only: this runs before every session's first prompt.
    func gaps() -> [String] {
        var gaps: [String] = []
        if !machine.hasMobileBuildMCP {
            gaps.append("MobileBuildMCP isn't installed, so its tools are missing: ask the person to run `brew install getsentry/xcodebuildmcp/mobilebuildmcp`, then restart Claude Code.")
        }
        if !project.hasMobileBuildMCPConfig {
            gaps.append("This project has no `.mobilebuildmcp/config.yaml`, so MobileBuildMCP has no profiles: offer `/xcrew:setup` before the first build or test.")
        }
        return gaps
    }
}
