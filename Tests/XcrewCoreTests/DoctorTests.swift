import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

@Suite struct DoctorTests {
    @Test func checkIDsAreUniqueAndNamespaced() async {
        let ids = Doctor.checks.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0.split(separator: "/").count == 2 })
    }

    @Test func worstIgnoresSkipsInAnyOrder() async {
        func entry(_ status: CheckStatus) -> Doctor.Entry { .init(check: LegacyBinaryCheck(), result: .init(status: status, message: "")) }
        #expect(Doctor.worst([entry(.pass), entry(.skip)]) == .pass)
        #expect(Doctor.worst([entry(.skip), entry(.warn)]) == .warn)
        #expect(Doctor.worst([entry(.warn), entry(.fail), entry(.pass)]) == .fail)
        // The setup skill and scripts read a full run's status: the same results give the same answer in any order.
        #expect(Doctor.worst([entry(.skip), entry(.pass)]) == .pass)
        #expect(Doctor.worst([entry(.skip), entry(.skip)]) == .skip)
    }


    static let latestRelease = "curl -fsSL --max-time 5 https://api.github.com/repos/breferrari/xcrew/releases/latest"

    @Test func anOlderXcrewIsToldHowToUpdate() async {
        let runner = FakeRunner(responses: [Self.latestRelease: .init(status: 0, stdout: #"{"tag_name":"v99.0.0","name":"Xcrew 99.0.0"}"#)])
        let result = await XcrewUpdateCheck().run(.fake(runner))
        #expect(result.status == .warn)
        #expect(result.message == "\(XcrewVersion.current) installed, 99.0.0 released: claude plugin update xcrew@breferrari, or turn on auto-update in /plugin → Marketplaces → breferrari")
    }

    @Test func theLatestXcrewPasses() async {
        let runner = FakeRunner(responses: [Self.latestRelease: .init(status: 0, stdout: #"{"tag_name":"v\#(XcrewVersion.current)"}"#)])
        #expect(await XcrewUpdateCheck().run(.fake(runner)) == .pass("\(XcrewVersion.current), the latest release"))
    }

    /// A checkout at `/Users/me/Dev/Xcrew`, a spelling git doesn't print, as the mod passes the plugin root unresolved.
    private func checkout(at root: String = "/Users/me/Dev/Xcrew", project: Project = .temporary(), prefix: String = "", status: CommandResult = .init(status: 0, stdout: ""), online: Bool = true, latest: String = XcrewVersion.current) -> CheckContext {
        var responses: [String: CommandResult] = [
            "git -C \(root) rev-parse --show-prefix --short HEAD": .init(status: 0, stdout: "\(prefix)\n5b646cc\n"),
            "git --no-optional-locks -C \(root) status --porcelain": status,
        ]
        if online { responses[Self.latestRelease] = .init(status: 0, stdout: #"{"tag_name":"v\#(latest)"}"#) }
        return .fake(FakeRunner(responses: responses), project: project, environment: ["XCREW_ROOT": root])
    }

    @Test func aGitCheckoutShowsItsCommit() async {
        #expect(await XcrewUpdateCheck().run(checkout()) == .pass("\(XcrewVersion.current) (5b646cc), the latest release"))
        #expect(await XcrewUpdateCheck().run(checkout(status: .init(status: 0, stdout: " M bin/xcrew\n"))) == .pass("\(XcrewVersion.current) (5b646cc + local changes), the latest release"))
    }

    /// A cached install inside a git-managed folder, such as a versioned `~/.claude`, isn't a checkout of Xcrew.
    @Test func aRepositoryAroundACachedInstallIsNotItsCommit() async {
        let result = await XcrewUpdateCheck().run(checkout(prefix: "plugins/cache/breferrari/xcrew/0.8.1/"))
        #expect(result == .pass("\(XcrewVersion.current), the latest release"))
    }

    /// A `git status` that fails prints nothing, which would read as a clean tree.
    @Test func aCommitWhoseTreeCantBeReadIsNotShown() async {
        #expect(await XcrewUpdateCheck().run(checkout(status: .init(status: 128, stdout: ""))) == .pass("\(XcrewVersion.current), the latest release"))
    }

    /// `claude plugin update` touches only the marketplace copy, never the checkout that runs.
    @Test func anOldCheckoutIsToldToPull() async {
        #expect(await XcrewUpdateCheck().run(checkout(latest: "99.0.0")) == .warn("\(XcrewVersion.current) (5b646cc) installed, 99.0.0 released: git pull in /Users/me/Dev/Xcrew"))
    }

    /// mcs loads the plugin from its own checkout of the pack, by its link or its real path: a `git pull` there would run
    /// commits nobody trusted.
    @Test(arguments: [".mcs/packs/xcrew", ".mcs/marketplaces/xcrew/plugins/xcrew"])
    func anOldMCSCheckoutIsToldToUpdateThroughMCS(_ path: String) async {
        let project = Project.temporary()
        let root = CheckContext.fake(project: project).machine.home.appending(path: path).path
        #expect(await XcrewUpdateCheck().run(checkout(at: root, project: project, latest: "99.0.0")) == .warn("\(XcrewVersion.current) (5b646cc) installed, 99.0.0 released: mcs update"))
    }

    /// `bin/xcrew` hands over the checkout's real path, which a symlinked `~/.mcs` doesn't spell.
    @Test func anMCSCheckoutBehindASymlinkedMCSFolderIsToldToUpdateThroughMCS() async throws {
        let project = Project.temporary(containing: ["home", "elsewhere/mcs/packs/xcrew"])
        try FileManager.default.createSymbolicLink(at: project.root.appending(path: "home/.mcs"), withDestinationURL: project.root.appending(path: "elsewhere/mcs"))
        let root = project.root.appending(path: "elsewhere/mcs/packs/xcrew").path
        #expect(await XcrewUpdateCheck().run(checkout(at: root, project: project, latest: "99.0.0")) == .warn("\(XcrewVersion.current) (5b646cc) installed, 99.0.0 released: mcs update"))
    }

    @Test func offlineTheCommitIsStillShown() async {
        #expect(await XcrewUpdateCheck().run(checkout(online: false)) == .skip("\(XcrewVersion.current) (5b646cc): couldn't reach GitHub to compare"))
    }

    @Test func noNetworkIsASkipNotAFailure() async {
        #expect(await XcrewUpdateCheck().run(.fake()).status == .skip)
        let garbled = FakeRunner(responses: [Self.latestRelease: .init(status: 0, stdout: "<html>rate limited</html>")])
        #expect(await XcrewUpdateCheck().run(.fake(garbled)).status == .skip)
    }

    @Test func versionCheck() async {
        let missing = await MobileBuildMCPVersionCheck().run(.fake())
        #expect(missing.status == .fail)

        let old = FakeRunner(installed: ["mobilebuildmcp"], responses: ["mobilebuildmcp --version": .init(status: 0, stdout: "2.7.0\n")])
        #expect(await MobileBuildMCPVersionCheck().run(.fake(old)).status == .fail)

        let new = FakeRunner(installed: ["mobilebuildmcp"], responses: ["mobilebuildmcp --version": .init(status: 0, stdout: "2.10.0\n")])
        #expect(await MobileBuildMCPVersionCheck().run(.fake(new)) == .pass("version 2.10.0"))
    }

    /// `mobilebuildmcp --version` is most of what the doctor costs, and the band reads the doctor after every prompt.
    @Test func theVersionIsKeptUntilTheBinaryChanges() async throws {
        let project = Project.temporary()
        project.write("", to: "bin/mobilebuildmcp")
        let binary = project.root.appending(path: "bin/mobilebuildmcp").path
        let environment = ["XCREW_CACHE": project.root.appending(path: "cache").path]
        var answering = FakeRunner(responses: ["mobilebuildmcp --version": .init(status: 0, stdout: "2.10.0\n")])
        answering.paths["mobilebuildmcp"] = binary
        var silent = FakeRunner()
        silent.paths["mobilebuildmcp"] = binary
        #expect(await MobileBuildMCPVersionCheck().run(.fake(answering, project: project, environment: environment)) == .pass("version 2.10.0"))
        #expect(await MobileBuildMCPVersionCheck().run(.fake(silent, project: project, environment: environment)) == .pass("version 2.10.0"))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: binary)
        #expect(await MobileBuildMCPVersionCheck().run(.fake(silent, project: project, environment: environment)).status == .fail)
    }

    @Test func legacyBinaryWarns() async {
        #expect(await LegacyBinaryCheck().run(.fake(FakeRunner(installed: ["xcodebuildmcp"]))).status == .warn)
        #expect(await LegacyBinaryCheck().run(.fake()).status == .pass)
    }

    /// mcs records the packs it configured in `.claude/.mcs-project`; only a project set up through it hears of mcs.
    @Test func theFixNamesMCSOnlyWhereMCSConfiguredXcrew() async {
        let project = Project.temporary(containing: ["A.xcworkspace"])
        project.write(#"{"configuredPacks":["other"]}"#, to: ".claude/.mcs-project")
        #expect(await ProjectConfigCheck().run(.fake(project: project)) == .fail("no .mobilebuildmcp/config.yaml: run /xcrew:setup"))
        project.write(#"{"configuredPacks":["xcrew"],"mcsVersion":"2.0.0"}"#, to: ".claude/.mcs-project")
        #expect(await ProjectConfigCheck().run(.fake(project: project)) == .fail("no .mobilebuildmcp/config.yaml: run /xcrew:setup (or, with the mcs CLI, mcs sync)"))
    }

    @Test func projectConfigCheck() async {
        let project = Project.temporary(containing: ["A.xcworkspace"])
        #expect(await ProjectConfigCheck().run(.fake(project: project)) == .fail("no .mobilebuildmcp/config.yaml: run /xcrew:setup"))

        project.write("enabledWorkflows:\n  - simulator\n", to: ".mobilebuildmcp/config.yaml")
        #expect(await ProjectConfigCheck().run(.fake(project: project)).status == .warn)

        project.write(ConfigRenderer.render(.init(container: "A.xcworkspace", testSimulator: "iPhone 17", testScheme: "A"), root: project.root), to: ".mobilebuildmcp/config.yaml")
        #expect(await ProjectConfigCheck().run(.fake(project: project)).status == .pass)

        project.write("", to: ".xcodebuildmcp/config.yaml")
        #expect(await ProjectConfigCheck().run(.fake(project: project)).status == .warn)
    }

    /// The tool groups as Xcrew 0.9.0 wrote them, with `xcode-ide` and without the status bar.
    static let groupsOf090 = "enabledWorkflows:\n  - simulator\n  - sim-env\n  - xcode-ide\n  - ui-automation\n  - debugging\ncustomWorkflows:\n  sim-env:\n    - erase_sims\n    - set_sim_appearance\n    - set_sim_location\n    - reset_sim_location\n    - toggle_software_keyboard\n    - toggle_connect_hardware_keyboard\n"

    static func config(groups: String, in project: Project) -> String {
        "schemaVersion: 1\n" + groups + "sessionDefaultsProfiles:\n  unit:\n    workspacePath: '\(project.root.path)/A.xcworkspace'\n    scheme: 'A'\n    simulatorName: 'iPhone 17'\nactiveSessionDefaultsProfile: unit\n"
    }

    /// A config an earlier Xcrew wrote has the tool groups it had then: setup brings them up to date.
    @Test func aConfigXcrewWroteWithEarlierToolGroupsIsOutdated() async {
        let project = Project.temporary(containing: ["A.xcworkspace"])
        project.write(Self.config(groups: Self.groupsOf090.replacingOccurrences(of: "  - xcode-ide\n", with: ""), in: project), to: ".mobilebuildmcp/config.yaml")
        project.write("", to: ".mobilebuildmcp/.xcrew-managed")
        #expect(await ProjectConfigCheck().run(.fake(project: project)) == .warn("the config Xcrew wrote has other tool groups than setup writes now: /xcrew:setup rewrites it"))
    }

    /// `xcode-ide` is a second route to the Xcode MCP that skips the mod's XcodeWrite guard, in any config.
    @Test func aConfigWithXcodeIDEWarnsWhoeverWroteIt() async {
        let project = Project.temporary(containing: ["A.xcworkspace"])
        project.write(Self.config(groups: Self.groupsOf090, in: project), to: ".mobilebuildmcp/config.yaml")
        project.write("", to: ".mobilebuildmcp/.xcrew-managed")
        let xcrews = "the config enables xcode-ide, MobileBuildMCP's second route to the Xcode MCP, which skips Xcrew's XcodeWrite guard: /xcrew:setup rewrites it"
        #expect(await ProjectConfigCheck().run(.fake(project: project)) == .warn(xcrews))
        try? FileManager.default.removeItem(at: project.managedMarker)
        #expect(await ProjectConfigCheck().run(.fake(project: project)) == .warn(xcrews + " (xcrew setup --force replaces a config xcrew didn't write)"))
    }

    /// MobileBuildMCP rewrites the config when Claude saves defaults with `persist`, after which setup keeps it: the fix
    /// says `--force`, since setup alone would leave it.
    @Test func aConfigEditedSinceXcrewWroteItNeedsForce() async {
        let project = Project.temporary(containing: ["A.xcworkspace"])
        project.write(Self.config(groups: Self.groupsOf090, in: project), to: ".mobilebuildmcp/config.yaml")
        project.write("0000", to: ".mobilebuildmcp/.xcrew-managed")
        #expect(await ProjectConfigCheck().run(.fake(project: project)) == .warn("the config enables xcode-ide, MobileBuildMCP's second route to the Xcode MCP, which skips Xcrew's XcodeWrite guard: /xcrew:setup rewrites it (xcrew setup --force replaces it, as it changed after Xcrew wrote it)"))
    }

    /// YAML says a list several ways, and the guard is skipped whichever one names `xcode-ide`; it's said first, since the
    /// warnings before it could hide it for good.
    @Test func xcodeIDEInAnyListFormIsFoundBeforeTheProfiles() async {
        let project = Project.temporary(containing: ["A.xcworkspace"])
        for groups in ["enabledWorkflows: [simulator, xcode-ide]\n", "enabledWorkflows:\n  - 'xcode-ide'  # bridge\n", "customWorkflows:\n  mine:\n    - xcode_ide_call_tool\n"] {
            project.write("schemaVersion: 1\n" + groups, to: ".mobilebuildmcp/config.yaml")
            #expect(await ProjectConfigCheck().run(.fake(project: project)).message.hasPrefix("the config enables xcode-ide"), "\(groups)")
        }
    }

    /// MobileBuildMCP writes the config back in its own style: the same groups, laid out differently, are up to date.
    @Test func theSameToolGroupsInAnotherLayoutAreCurrent() async {
        let project = Project.temporary(containing: ["A.xcworkspace"])
        let groups = "enabledWorkflows:\n    - \"debugging\"\n    - simulator\n    - ui-automation\n    - sim-env\ncustomWorkflows:\n    sim-env:\n        - toggle_connect_hardware_keyboard\n        - erase_sims\n        - set_sim_appearance\n        - set_sim_location\n        - reset_sim_location\n        - sim_statusbar\n        - toggle_software_keyboard\n"
        project.write(Self.config(groups: groups, in: project), to: ".mobilebuildmcp/config.yaml")
        project.write("", to: ".mobilebuildmcp/.xcrew-managed")
        #expect(await ProjectConfigCheck().run(.fake(project: project)).status == .pass)
    }

    /// A config of the person's own with other groups is theirs to choose, short of `xcode-ide`.
    @Test func aConfigOfThePersonsOwnWithOtherToolGroupsPasses() async {
        let project = Project.temporary(containing: ["A.xcworkspace"])
        project.write(Self.config(groups: "enabledWorkflows:\n  - simulator\n  - session-management\n", in: project), to: ".mobilebuildmcp/config.yaml")
        #expect(await ProjectConfigCheck().run(.fake(project: project)).status == .pass)
    }

    /// Configs from 0.8.1 and earlier have a schemeless `unit` profile active.
    @Test func anActiveProfileWithoutASchemeWarns() async {
        let project = Project.temporary(containing: ["A.xcworkspace"])
        project.write("schemaVersion: 1\nenabledWorkflows:\n  - simulator\nsessionDefaultsProfiles:\n  unit:\n    workspacePath: '\(project.root.path)/A.xcworkspace'\n    simulatorName: 'iPhone 17'\nactiveSessionDefaultsProfile: unit\n", to: ".mobilebuildmcp/config.yaml")
        #expect(await ProjectConfigCheck().run(.fake(project: project)) == .warn("the active profile, unit, has no scheme, so a build or test has nothing to run: rerun /xcrew:setup (xcrew setup --force replaces a config xcrew didn't write)"))
    }

    @Test func aConfigWithoutProfilesWarns() async {
        let project = Project.temporary(containing: ["A.xcworkspace"])
        project.write(ConfigRenderer.render(.init(container: "A.xcworkspace", testSimulator: "iPhone 17"), root: project.root), to: ".mobilebuildmcp/config.yaml")
        #expect(await ProjectConfigCheck().run(.fake(project: project)) == .warn("no profile has a scheme yet, so a build or test needs one each time: /xcrew:setup adds them from your schemes"))
    }

    @Test func aSimulatorIDThatIsGoneWarns() async {
        let project = Project.temporary()
        project.write(ConfigRenderer.render(.init(container: "A.xcworkspace", testSimulator: "iPhone 17", testScheme: "A"), root: project.root, simulatorIDs: ["iPhone 17": "GONE"]), to: ".mobilebuildmcp/config.yaml")
        let json = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone 17","udid":"NEW","isAvailable":true}]}}"#
        let runner = FakeRunner(responses: ["xcrun simctl list devices available --json": .init(status: 0, stdout: json)])
        #expect(await SimulatorsCheck().run(.fake(runner, project: project)) == .warn("a simulator the profiles name by ID is gone (GONE): xcrew setup writes the current ones"))
    }

    @Test func simulatorsCheckNamesWhatIsMissing() async {
        let project = Project.temporary()
        project.write(ConfigRenderer.render(.init(container: "A.xcworkspace", testSimulator: "iPhone 17", appSimulator: "iPhone 99", appScheme: "A"), root: project.root), to: ".mobilebuildmcp/config.yaml")
        let json = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone 17","isAvailable":true}]}}"#
        let runner = FakeRunner(responses: ["xcrun simctl list devices available --json": .init(status: 0, stdout: json)])
        let result = await SimulatorsCheck().run(.fake(runner, project: project))
        #expect(result.status == .warn)
        #expect(result.message.contains("iPhone 99"))
        #expect(!result.message.contains("iPhone 17,"))
    }

    /// Setup in 0.8.2 could name the iPhone Duo, and a person can name it; `screenshot` fails on it either way.
    @Test func aSimulatorWithTwoDisplaysWarns() async {
        let project = Project.temporary()
        project.write(ConfigRenderer.render(.init(container: "A.xcworkspace", testSimulator: "iPhone Duo", testScheme: "A"), root: project.root), to: ".mobilebuildmcp/config.yaml")
        let devices = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-2":[{"name":"iPhone Duo","isAvailable":true,"deviceTypeIdentifier":"duo"}]}}"#
        let runner = FakeRunner(responses: [
            "xcrun simctl list devices available --json": .init(status: 0, stdout: devices),
            "xcrun simctl list devicetypes --json": .init(status: 0, stdout: #"{"devicetypes":[{"identifier":"duo","bundlePath":"/Profiles/Duo.simdevicetype"}]}"#),
            "plutil -extract capabilities.displays json -o - /Profiles/Duo.simdevicetype/Contents/Resources/capabilities.plist": .init(status: 0, stdout: #"[{"powerState":1},{"powerState":1}]"#),
        ])
        #expect(await SimulatorsCheck().run(.fake(runner, project: project)) == .warn("iPhone Duo has two displays, and MobileBuildMCP's screenshot fails on it: xcrew setup --test-simulator <name> picks another"))
    }

    /// Two sessions on one project: Claude Code 100 with its server 200 and this doctor, 300; Claude Code 400 with its server 500.
    func sessions(project: Project, mine: String, theirs: String, configAgo seconds: TimeInterval) throws -> FakeRunner {
        project.write("schemaVersion: 1\n", to: ".mobilebuildmcp/config.yaml")
        project.write("", to: ".mobilebuildmcp/.xcrew-managed")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -seconds)], ofItemAtPath: project.managedMarker.path)
        let ps = """
          100     1 01:00:00 /Users/me/.local/bin/claude --resume
          200   100 \(mine) \(Self.server)
          300   100    00:01 /plugins/xcrew/.build/xcrew doctor --problems --json
          400     1 01:00:00 claude
          500   400 \(theirs) \(Self.server)
          600     1    00:01 /plugins/xcrew/.build/xcrew doctor
        """
        let comm = "100 /Users/me/.local/bin/claude\n200 node-runtime\n300 xcrew\n400 claude\n500 node-runtime\n600 xcrew\n"
        return runner(ps: ps, comm: comm, cwd: [200, 500], project: project)
    }

    @Test func thisSessionsServerHasTheConfigItStartedAfter() async throws {
        let project = Project.temporary()
        let runner = try sessions(project: project, mine: "00:30", theirs: "10:00", configAgo: 60)
        #expect(await ConfigLoadedCheck().run(.fake(runner, project: project, processID: 300)).status == .pass)
    }

    @Test func aConfigNewerThanThisSessionsServerAsksForARestart() async throws {
        let project = Project.temporary()
        let runner = try sessions(project: project, mine: "05:00", theirs: "00:30", configAgo: 60)
        #expect(await ConfigLoadedCheck().run(.fake(runner, project: project, processID: 300)) == .warn("the config changed after this session's MobileBuildMCP started: restart Claude Code to load it"))
    }

    /// From a terminal there's no session to match, so the oldest server for the project stands for any stale one.
    @Test func fromATerminalTheOldestServerCounts() async throws {
        let project = Project.temporary()
        let runner = try sessions(project: project, mine: "00:30", theirs: "1-02:10:00", configAgo: 60)
        #expect(await ConfigLoadedCheck().run(.fake(runner, project: project, processID: 600)) == .warn("a MobileBuildMCP serving this project started before the config changed: restart its Claude Code session to load it"))
    }

    /// MobileBuildMCP saves session defaults with `persist: true` into its own config, which it already holds.
    @Test func theServersOwnWriteAsksForNoRestart() async throws {
        let project = Project.temporary()
        let runner = try sessions(project: project, mine: "00:30", theirs: "10:00", configAgo: 60)
        project.write("schemaVersion: 1\nactiveSessionDefaultsProfile: app\n", to: ".mobilebuildmcp/config.yaml")
        #expect(await ConfigLoadedCheck().run(.fake(runner, project: project, processID: 300)).status == .pass)
    }

    static let server = FakeSession.server

    func runner(ps: String, comm: String, cwd: [Int32], project: Project) -> FakeRunner {
        var responses: [String: CommandResult] = [
            "ps -axo pid=,ppid=,etime=,command=": .init(status: 0, stdout: ps),
            "ps -axo pid=,comm=": .init(status: 0, stdout: comm),
            "lsof -a -p \(cwd.map(String.init).joined(separator: ",")) -d cwd -Fn": .init(status: 0, stdout: cwd.map { "p\($0)\nfcwd\nn\(project.root.path)\n" }.joined()),
        ]
        for pid in cwd { responses["lsof -a -p \(pid) -d cwd -Fn"] = .init(status: 0, stdout: "p\(pid)\nfcwd\nn\(project.root.path)\n") }
        return FakeRunner(responses: responses)
    }

    /// The desktop app runs Claude Code from a folder with a space in its path, which a command line can't be split at.
    @Test func aClaudeCodeInAFolderWithSpacesIsTheSession() async throws {
        let project = Project.temporary()
        project.write("", to: ".mobilebuildmcp/.xcrew-managed")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: project.managedMarker.path)
        let claude = "/Users/me/Library/Application Support/Claude/claude-code/1.0/claude"
        let ps = "  100 1 01:00:00 \(claude) --resume\n  200 100 05:00 \(Self.server)\n  300 100 00:01 /plugins/xcrew/.build/xcrew doctor\n  400 1 01:00:00 claude\n  500 400 10:00 \(Self.server)\n"
        let comm = "  100 \(claude)\n  200 /opt/homebrew/Cellar/mobilebuildmcp/2.7.1/libexec/node-runtime\n  300 /plugins/xcrew/.build/xcrew\n  400 /Users/me/.local/bin/claude\n  500 /opt/homebrew/Cellar/mobilebuildmcp/2.7.1/libexec/node-runtime\n"
        #expect(await ConfigLoadedCheck().run(.fake(runner(ps: ps, comm: comm, cwd: [200, 500], project: project), project: project, processID: 300)) == .warn("the config changed after this session's MobileBuildMCP started: restart Claude Code to load it"))
    }

    /// A server whose Claude Code exited is adopted by launchd; no session owns it, so no restart reaches it.
    @Test func anOrphanedServerIsNobodysToRestart() async throws {
        let project = Project.temporary()
        project.write("", to: ".mobilebuildmcp/.xcrew-managed")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: project.managedMarker.path)
        let ps = "  400 1 01:00:00 claude\n  500 400 00:30 \(Self.server)\n  700 1 10:00 \(Self.server)\n  600 1 00:01 /plugins/xcrew/.build/xcrew doctor\n"
        let comm = "  400 claude\n  500 node-runtime\n  700 node-runtime\n  600 xcrew\n"
        #expect(await ConfigLoadedCheck().run(.fake(runner(ps: ps, comm: comm, cwd: [500, 700], project: project), project: project, processID: 600)).status == .pass)
    }

    @Test func withNoServerRunningTheCheckSkips() async throws {
        let project = Project.temporary()
        project.write("", to: ".mobilebuildmcp/.xcrew-managed")
        let runner = FakeRunner(responses: ["ps -axo pid=,ppid=,etime=,command=": .init(status: 0, stdout: "  1 0 01:00 /sbin/launchd\n")])
        #expect(await ConfigLoadedCheck().run(.fake(runner, project: project, processID: 600)) == .skip("MobileBuildMCP isn't running for this project"))
    }

    @Test func xcodeMCPChecks() async {
        let enabled = FakeRunner(responses: ["xcrun mcp-server status": .init(status: 0, stdout: "Permission: enabled\nApproved agents:\n  com.anthropic.claude-code\n")])
        #expect(await HeadlessXcodeMCPCheck().run(.fake(enabled)).status == .pass)
        #expect(await ClaudeApprovedCheck().run(.fake(enabled)).status == .pass)

        let disabled = FakeRunner(responses: ["xcrun mcp-server status": .init(status: 0, stdout: "Permission: disabled\n")])
        #expect(await HeadlessXcodeMCPCheck().run(.fake(disabled)).status == .fail)
        #expect(await ClaudeApprovedCheck().run(.fake(disabled)).status == .warn)

        #expect(await HeadlessXcodeMCPCheck().run(.fake()).status == .fail)
        #expect(await ClaudeApprovedCheck().run(.fake()).status == .skip)
    }

    @Test func unsignedAgentsCheck() async {
        let on = FakeRunner(responses: ["defaults read com.apple.dt.Xcode IDEAllowUnauthenticatedAgents": .init(status: 0, stdout: "1\n")])
        #expect(await UnsignedAgentsCheck().run(.fake(on)).status == .warn)
        #expect(await UnsignedAgentsCheck().run(.fake()).status == .pass)
    }
}

@Suite struct StaleConfigTests {
    @Test func aConfigPointingAtAContainerThatIsGoneWarns() async {
        let project = Project.temporary(containing: ["Renamed.xcworkspace"])
        project.write(ConfigRenderer.render(.init(container: "App.xcworkspace", testSimulator: "iPhone 17", testScheme: "App"), root: project.root), to: ".mobilebuildmcp/config.yaml")
        let result = await ProjectConfigCheck().run(.fake(project: project))
        #expect(result.status == .warn)
        #expect(result.message.contains("App.xcworkspace") && result.message.contains("xcrew setup"))
    }
}

@Suite struct DoctorProblemsTests {
    struct Fixed: Check {
        let id: String
        let title = "fixed"
        let status: CheckStatus
        func run(_ context: CheckContext) async -> CheckResult { CheckResult(status: status, message: id) }
    }

    @Test func problemsAreWhatFailedOrWarnedWorstFirst() async {
        let checks: [any Check] = [Fixed(id: "a/ok", status: .pass), Fixed(id: "b/warn", status: .warn), Fixed(id: "c/fail", status: .fail), Fixed(id: "d/skip", status: .skip)]
        let entries = await Doctor.run(checks, in: .fake())
        #expect(Doctor.problems(entries).map(\.check.id) == ["c/fail", "b/warn"])
    }
}

@Suite struct MCPServerStatusTests {
    /// Answers every call and counts how many asked for the Xcode MCP's status.
    final class CountingRunner: CommandRunning, @unchecked Sendable {
        private let lock = NSLock()
        private var statuses = 0
        var statusCalls: Int { lock.withLock { statuses } }

        func run(_ argv: [String], stdin: Data?, timeout: Duration) async -> CommandResult {
            if argv == ["xcrun", "mcp-server", "status"] { lock.withLock { statuses += 1 } }
            return CommandResult(status: 0, stdout: "Permission: enabled\ncom.anthropic.claude-code")
        }

        func which(_ name: String) -> String? { nil }
    }

    @Test func oneDoctorRunAsksTheXcodeMCPForItsStatusOnce() async {
        let runner = CountingRunner()
        let project = Project.temporary()
        let context = CheckContext(project: project, machine: Machine(environment: [:], home: project.root, runner: runner))
        let entries = await Doctor.run(Doctor.checks.filter { $0.id.hasPrefix("xcode-mcp/headless") || $0.id.hasPrefix("xcode-mcp/claude") }, in: context)
        #expect(entries.map(\.result.status) == [.pass, .pass])
        #expect(runner.statusCalls == 1)
    }
}
