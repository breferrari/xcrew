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
    private func checkout(prefix: String = "", status: CommandResult = .init(status: 0, stdout: ""), online: Bool = true, latest: String = XcrewVersion.current) -> CheckContext {
        var responses: [String: CommandResult] = [
            "git -C /Users/me/Dev/Xcrew rev-parse --show-prefix --short HEAD": .init(status: 0, stdout: "\(prefix)\n5b646cc\n"),
            "git --no-optional-locks -C /Users/me/Dev/Xcrew status --porcelain": status,
        ]
        if online { responses[Self.latestRelease] = .init(status: 0, stdout: #"{"tag_name":"v\#(latest)"}"#) }
        return .fake(FakeRunner(responses: responses), environment: ["XCREW_ROOT": "/Users/me/Dev/Xcrew"])
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

    /// Configs from 0.8.1 and earlier have a schemeless `unit` profile active.
    @Test func anActiveProfileWithoutASchemeWarns() async {
        let project = Project.temporary(containing: ["A.xcworkspace"])
        project.write("schemaVersion: 1\nenabledWorkflows:\n  - xcode-ide\nsessionDefaultsProfiles:\n  unit:\n    workspacePath: '\(project.root.path)/A.xcworkspace'\n    simulatorName: 'iPhone 17'\nactiveSessionDefaultsProfile: unit\n", to: ".mobilebuildmcp/config.yaml")
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
