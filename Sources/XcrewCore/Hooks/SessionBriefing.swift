import Foundation

/// What a Claude Code session in an Apple-platform project starts with: the routing rules, the
/// profiles this project's config defines, the Xcode it pins, the simulators booted now, the test plans that run each
/// test under several configurations, then whatever this Mac or project still lacks.
/// Silent in any other project.
public struct SessionBriefing: Sendable {
    let project: Project
    let machine: Machine

    public init(project: Project, machine: Machine) {
        self.project = project
        self.machine = machine
    }

    public func text(routing: String) async -> String? {
        let layout = project.layout(.repository)
        guard layout.isApplePlatform else { return nil }
        let containers = layout.containers.map { project.root.appending(path: $0) }
        async let plans = Self.testPlans(in: containers)
        async let offer = project.hasSchemeToBuild ? nil : Self.setupOffer(for: project, using: machine.runner)
        async let status = MobileBuildMCPStatus.assess(machine, timeout: Self.versionTimeout)
        async let bootedNow = booted()
        async let head = GitHead.of(project, using: machine.runner)
        let mobileBuildMCP = await status
        let failover = mobileBuildMCP.failsOver ? mobileBuildMCP.problem.map { Self.failoverNote(reason: "\($0.reason): ask the person to run `\($0.fix)`, then restart Claude Code") } : nil
        let notes = [failover, failover == nil ? profiles() : nil, pinnedXcode(), bootedNote(await bootedNow)].compactMap { $0 } + (await plans) + [await offer].compactMap { $0 }
        let lines = [routing.trimmingCharacters(in: .whitespacesAndNewlines)] + notes.map { "- **xcrew:** \($0)" }
        let card = ProjectCard.text(folder: project.canonicalRoot, branch: ProjectCard.branchKey(await head), now: Date(), on: machine)
        return lines.joined(separator: "\n") + (card.map { "\n\n" + $0 } ?? "")
    }

    /// The Xcode the project pins, read from its file alone: whether the server started with it is the doctor's to say,
    /// so this claims no more than that it starts with it when it can.
    func pinnedXcode() -> String? {
        project.xcodePin.map { "This project pins Xcode \($0.version) (`\($0.file)`). MobileBuildMCP starts with it when it's installed and xcrew's CLI is ready, and `xcrew doctor` says when it didn't. The Xcode MCP works through whichever Xcode is open." }
    }

    /// Each test plan the schemes run by default that tests under several configurations, so Claude knows a test can fail
    /// under one and pass under another, and that `look` says which; a few at most, the rest counted. Read beside the
    /// other checks, since a large workspace has many schemes to read.
    static func testPlans(in containers: [URL]) async -> [String] {
        let (plans, complete) = TestPlans.configured(containers: containers)
        let named = plans.prefix(ResultBundle.mostNamed).map { found in
            let schemes = String(ResultBundle.listed(found.schemes.map { "`\($0)`" }).dropFirst(2))
            return "Test plan `\(found.plan)`, the default of \(found.schemes.count == 1 ? "scheme" : "schemes") \(schemes), runs each test under each of its configurations\(ResultBundle.listed(found.configurations)). A test can fail under one and pass under another; `look` names which."
        }
        let more = plans.count - named.count
        let counted = complete ? "\(more)" : "at least \(more)"
        return named + (more > 0 || !complete ? ["and \(counted) more test \(more == 1 && complete ? "plan runs" : "plans run") each test under several configurations."] : [])
    }

    /// Said at the start, and by the mod with the session's first MobileBuildMCP build or test, while MobileBuildMCP has
    /// no scheme to build with.
    public static let setupOffer = "MobileBuildMCP has no scheme to build this project with yet. `/xcrew:setup` writes its profiles once, from the project's schemes and simulators, and can be offered to the person."

    func profiles() -> String? {
        guard let yaml = try? String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8) else { return nil }
        let profiles = ConfigRenderer.profiles(in: yaml)
        guard !profiles.names.isEmpty else { return nil }
        let named = profiles.names.map { "`\($0)`" + ($0 == profiles.active ? " (active)" : "") }
        return "MobileBuildMCP profiles here: \(named.joined(separator: ", ")). Switch with `session_use_defaults_profile`."
    }

    /// How long the briefing waits for `mobilebuildmcp --version` when its cache is cold: about half a second after an
    /// upgrade (docs/findings.md), and a version it can't read in time doesn't fail over.
    static let versionTimeout = Duration.seconds(2)

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
        return "Simulators booted now: \(named.joined(separator: ", ")). One can be reused rather than booting another."
    }

    /// What Claude does while MobileBuildMCP can't serve: the Xcode MCP's build and test tools, what they lose, and the
    /// one change to the person's own Xcode, its active scheme, that waits for their word.
    static func failoverNote(reason: String) -> String {
        "MobileBuildMCP isn't usable here (\(reason)), so its build and test tools aren't either. Until it is, the routing rules' MobileBuildMCP rows don't apply: build with the Xcode MCP's `BuildProject` and test with `RunAllTests`. They work through Xcode itself, on the open project, its active scheme and destination, in Xcode's own DerivedData. Lost meanwhile: coverage reports, simulator control, UI automation and LLDB. Tell the person once that MobileBuildMCP is unavailable and what that loses, then carry on. If a build or test needs a scheme other than Xcode's active one, ask before switching it: that changes their open Xcode. If the Xcode MCP's tools refuse too, run `xcrew doctor`."
    }

    /// The setup to offer a project with no scheme to build: in a worktree whose main checkout has a config, the one
    /// that copies it.
    public static func setupOffer(for project: Project, using runner: any CommandRunning) async -> String {
        await Worktree.takesMainConfig(project, using: runner) ? Worktree.setupOffer : setupOffer
    }
}
