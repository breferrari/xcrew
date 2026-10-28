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

    @Test func worstIgnoresSkips() async {
        func entry(_ status: CheckStatus) -> Doctor.Entry { .init(check: LegacyBinaryCheck(), result: .init(status: status, message: "")) }
        #expect(Doctor.worst([entry(.pass), entry(.skip)]) == .pass)
        #expect(Doctor.worst([entry(.skip), entry(.warn)]) == .warn)
        #expect(Doctor.worst([entry(.warn), entry(.fail), entry(.pass)]) == .fail)
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

    @Test func legacyBinaryWarns() async {
        #expect(await LegacyBinaryCheck().run(.fake(FakeRunner(installed: ["xcodebuildmcp"]))).status == .warn)
        #expect(await LegacyBinaryCheck().run(.fake()).status == .pass)
    }

    @Test func projectConfigCheck() async {
        let project = Project.temporary(containing: ["A.xcworkspace"])
        #expect(await ProjectConfigCheck().run(.fake(project: project)).status == .fail)

        project.write("enabledWorkflows:\n  - simulator\n", to: ".mobilebuildmcp/config.yaml")
        #expect(await ProjectConfigCheck().run(.fake(project: project)).status == .warn)

        project.write(ConfigRenderer.render(.init(container: "A.xcworkspace", testSimulator: "iPhone 17"), root: project.root), to: ".mobilebuildmcp/config.yaml")
        #expect(await ProjectConfigCheck().run(.fake(project: project)).status == .pass)

        project.write("", to: ".xcodebuildmcp/config.yaml")
        #expect(await ProjectConfigCheck().run(.fake(project: project)).status == .warn)
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
        project.write(ConfigRenderer.render(.init(container: "App.xcworkspace", testSimulator: "iPhone 17"), root: project.root), to: ".mobilebuildmcp/config.yaml")
        let result = await ProjectConfigCheck().run(.fake(project: project))
        #expect(result.status == .warn)
        #expect(result.message.contains("App.xcworkspace") && result.message.contains("xcrew setup"))
    }
}
