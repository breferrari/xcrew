import Foundation

/// What a Claude Code session in an Apple-platform project starts with: the routing rules, the
/// profiles this project's config defines, the simulators booted now, then whatever this Mac or project still lacks.
/// Silent in any other project.
public struct SessionBriefing: Sendable {
    let project: Project
    let machine: Machine

    public init(project: Project, machine: Machine) {
        self.project = project
        self.machine = machine
    }

    public func text(routing: String) async -> String? {
        guard project.isApplePlatformProject else { return nil }
        let notes = [profiles(), bootedNote(await booted())].compactMap { $0 } + gaps()
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

    /// How long the briefing waits for `simctl`, after which the runner takes up to its grace to stop it (docs/findings.md).
    static let simctlTimeout = Duration.seconds(1)
    static let coreSimulatorService = "com.apple.CoreSimulator.CoreSimulatorService"

    /// The simulators booted now. Only a running CoreSimulator service has any, and `xcrun` without one starts it, or on
    /// a Mac without the developer tools offers to install them, so `simctl` is asked only while the service runs.
    func booted() async -> [SimulatorCatalog.Device] {
        guard await machine.runner.run("pgrep", "-x", Self.coreSimulatorService, timeout: Self.simctlTimeout).status == 0 else { return [] }
        return await SimulatorCatalog.booted(using: machine.runner, timeout: Self.simctlTimeout)
    }

    /// Each with its UDID, since a name can be installed on several runtimes and only one of them is booted.
    func bootedNote(_ booted: [SimulatorCatalog.Device]) -> String? {
        guard !booted.isEmpty else { return nil }
        let named = booted.map { device in
            let details = ["\(device.platform) \(device.runtimeVersion)", device.udid, device.state == "Booting" ? "booting" : nil].compactMap { $0 }
            return "\(device.name) (\(details.joined(separator: ", ")))"
        }
        return "Simulators booted now: \(named.joined(separator: ", ")). Reuse one rather than booting another."
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
