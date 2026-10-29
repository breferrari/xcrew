import Foundation

/// What a Claude Code session in an Apple-platform project starts with: the routing rules, the
/// profiles this project's config defines, then whatever this Mac or project still lacks. Silent in any other project.
public struct SessionBriefing: Sendable {
    let project: Project
    let machine: Machine

    public init(project: Project, machine: Machine) {
        self.project = project
        self.machine = machine
    }

    public func text(routing: String) -> String? {
        guard project.isApplePlatformProject else { return nil }
        let notes = (profiles().map { [$0] } ?? []) + gaps()
        let lines = [routing.trimmingCharacters(in: .whitespacesAndNewlines)] + notes.map { "- **xcrew:** \($0)" }
        return lines.joined(separator: "\n")
    }

    func profiles() -> String? {
        guard let yaml = try? String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8) else { return nil }
        let profiles = ConfigRenderer.profiles(in: yaml)
        guard !profiles.names.isEmpty else { return nil }
        let named = profiles.names.map { "`\($0)`" + ($0 == profiles.active ? " (active)" : "") }
        return "MobileBuildMCP profiles here: \(named.joined(separator: ", ")). Switch with `session_use_defaults_profile`."
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
