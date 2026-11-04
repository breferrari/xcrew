import Foundation

/// What a Claude Code session in an Apple-platform project starts with: the routing rules, the profiles this project's
/// config defines, the Xcode it pins, the simulators booted now, whatever this Mac or project still lacks, the project
/// card, then the test plans that run each test under several configurations. Claude Code passes on 10,000 characters
/// of a session-start hook's context, so what can run long comes last and names a few.
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
        async let status = MobileBuildMCPStatus.assess(machine)
        async let bootedNow = booted()
        async let head = GitHead.of(project, using: machine.runner)
        async let simulatorApp = simulatorApp()
        let mobileBuildMCP = await status
        let failover = mobileBuildMCP.failsOver ? mobileBuildMCP.problem.map { Self.failoverNote(reason: "\($0.reason): ask the person to run `\($0.fix)`, then restart Claude Code") } : nil
        let notes = [failover, failover == nil ? profiles() : nil, pinnedXcode(), await simulatorApp, bootedNote(await bootedNow), await offer].compactMap { $0 }
        let lines = [routing.trimmingCharacters(in: .whitespacesAndNewlines)] + notes.map { "- **xcrew:** \($0)" }
        let card = ProjectCard.text(folder: project.canonicalRoot, branch: ProjectCard.branchKey(await head), on: machine)
        let planned = (await plans).map { "- **xcrew:** \($0)" }
        return lines.joined(separator: "\n") + (card.map { "\n\n" + $0 } ?? "") + (planned.isEmpty ? "" : "\n\nTest plans here:\n" + planned.joined(separator: "\n"))
    }

    /// The Xcode the project pins, read from its file alone: whether the server started with it is the doctor's to say,
    /// so this claims no more than that it starts with it when it can.
    func pinnedXcode() -> String? {
        project.xcodePin.map { "This project pins Xcode \($0.version) (`\($0.file)`). MobileBuildMCP starts with it when it's installed and xcrew's CLI is ready, and `xcrew doctor` says when it didn't. The Xcode MCP works through whichever Xcode is open." }
    }

    /// The selected Xcode's simulator app when it's DeviceHub, as from Xcode 27, and no Xcode in the applications folder
    /// has a Simulator.app for `open -a Simulator` to open.
    func simulatorApp() async -> String? {
        guard let xcode = await Xcodes.selected(on: machine), xcode.hasDeviceHubOnly(files: machine.files),
              !Xcodes.applications(on: machine).compactMap({ Xcodes.install(at: $0, files: machine.files) }).contains(where: { $0.hasSimulatorApp(files: machine.files) })
        else { return nil }
        return Self.deviceHubNote(xcode.label)
    }

    static func deviceHubNote(_ xcode: String) -> String {
        "\(xcode) shows simulators in DeviceHub (`open -a DeviceHub`); no Xcode here has Simulator.app."
    }

    /// Each test plan the schemes run by default that tests under several configurations, so Claude knows a test can fail
    /// under one and pass under another, and that `look` says which; a few at most, the rest counted. Read beside the
    /// other checks, since a large workspace has many schemes to read.
    static func testPlans(in containers: [URL]) async -> [String] {
        let plans = TestPlans.configured(containers: containers)
        let named = plans.prefix(ResultBundle.mostNamed).map { found in
            "\(found.sentence) A test can fail under one and pass under another; `look` names which."
        }
        let more = plans.count - named.count
        if more == 0 { return named }
        return named + ["and \(more) more test \(more == 1 ? "plan runs" : "plans run") each test under several configurations (\(TestPlans.listedBy))."]
    }

    /// Said at the start, and by the mod with the session's first MobileBuildMCP build or test, while MobileBuildMCP has
    /// no scheme to build with.
    public static let setupOffer = "MobileBuildMCP has no scheme to build this project with yet. `/xcrew:setup` writes its profiles once, from the project's schemes and simulators, and can be offered to the person, who can also pick them in the form `/xcrew setup` opens."

    func profiles() -> String? {
        guard let yaml = try? String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8) else { return nil }
        let profiles = ConfigRenderer.profiles(in: yaml)
        guard !profiles.names.isEmpty else { return nil }
        let named = profiles.names.map { "`\($0)`" + ($0 == profiles.active ? " (active)" : "") }
        return "MobileBuildMCP profiles here: \(named.joined(separator: ", ")). Switch with `session_use_defaults_profile`."
    }

    /// The simulators booted now, or none when `simctl` can't say in time (`SimulatorCatalog.bootedIfServiceRuns`).
    func booted() async -> [SimulatorCatalog.Device] {
        await SimulatorCatalog.bootedIfServiceRuns(using: machine.runner) ?? []
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
