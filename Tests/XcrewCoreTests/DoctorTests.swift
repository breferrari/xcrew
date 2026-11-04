import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

@Suite struct DoctorTests {
    /// The tests' own time, which the servers' starts and the configs' writes are dated against.
    static let now = Date(timeIntervalSince1970: 1_767_225_600)

    /// What scans the disk, this project's storage and the simulators setup left for worktrees, is said by `xcrew space`
    /// when asked, never by the doctor.
    @Test func theDoctorScansNoDisk() {
        let ids = Doctor.checks.map(\.id)
        #expect(!ids.contains("mobilebuildmcp/storage"))
        #expect(!ids.contains("simulators/worktree-leftovers"))
    }

    /// The doctor checks what xcrew can't run without, the installation and the toolchain, and nothing else: anything
    /// more is a note on the failure it explains, a part of `xcrew space`, or a line of setup's.
    @Test func theDoctorHoldsWhatXcrewNeedsToRunAndNothingElse() {
        #expect(Doctor.checks.map(\.id) == [
            "mobilebuildmcp/version", "mobilebuildmcp/no-legacy-binary", "mobilebuildmcp/project-config", "mobilebuildmcp/config-loaded", "mobilebuildmcp/simulators",
            "xcode-mcp/headless-enabled", "xcode-mcp/handshake", "xcode/pin", "xcode-mcp/claude-approved",
            "xcrew/briefing-current", "xcrew/mod-loaded",
        ])
    }

    /// The doctor reaches no network, the full one included: the plugin system handles updates.
    @Test func theDoctorReachesNoNetwork() async {
        let project = Project.temporary(containing: ["App.xcworkspace"])
        let runner = RecordingRunner(FakeRunner(responses: [:]))
        _ = await Doctor.run(in: CheckContext(project: project, machine: Machine(environment: [:], home: project.root, runner: runner, applications: project.root.appending(path: "Applications"), files: RootedFiles(roots: [project.root]))))
        #expect(!runner.asked.contains { $0.hasPrefix("curl ") }, "\(runner.asked)")
    }

    @Test func checkIDsAreUniqueAndNamespaced() async {
        let ids = Doctor.checks.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0.split(separator: "/").count == 2 })
    }

    /// A doctor run looks at the Mac's Xcodes once, however many checks read them, and sizes no workspace: both were what
    /// made `xcrew doctor` slow, and `xcrew space` sizes them when asked.
    @Test func aRunLooksAtTheXcodesOnceAndSizesNoWorkspace() async {
        let project = Project.temporary(containing: ["A.xcworkspace"])
        project.write("26.4\n", to: ".xcode-version")
        let runner = RecordingRunner(FakeRunner(installed: ["mobilebuildmcp", "xcodes"], responses: [:]))
        _ = await Doctor.run(in: CheckContext(project: project, machine: Machine(environment: [:], home: project.root, runner: runner, applications: project.root.appending(path: "Applications"), files: RootedFiles(roots: [project.root]))))
        #expect(runner.asked.filter { $0 == "xcode-select -p" }.count == 1, "\(runner.asked)")
        let reports = runner.asked.filter { $0.hasPrefix("mobilebuildmcp purge --report") }
        #expect(reports.isEmpty, "\(reports)")
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
        let old = await LegacyBinaryCheck().run(.fake(FakeRunner(installed: ["xcodebuildmcp"])))
        #expect(old.status == .warn)
        #expect(old.message.hasSuffix(". Uninstalling it removes a tool of the person's, so it's the person's to agree to: brew uninstall xcodebuildmcp, or npm uninstall -g xcodebuildmcp"), "\(old.message)")
        #expect(await LegacyBinaryCheck().run(.fake()).status == .pass)
    }

    /// mcs records the packs it configured in `.claude/.mcs-project`; only a project set up through it hears of mcs.
    @Test func theFixNamesMCSOnlyWhereMCSConfiguredXcrew() async {
        let project = Project.temporary(containing: ["A.xcworkspace"])
        project.write(#"{"configuredPacks":["other"]}"#, to: ".claude/.mcs-project")
        #expect(await ProjectConfigCheck().run(.fake(project: project)) == .fail("no .mobilebuildmcp/config.yaml: run /xcrew:setup"))
        // In a worktree whose main checkout has one, the fix copies it.
        let main = Project.temporary(containing: ["App.xcodeproj"])
        main.write("schemaVersion: 1\nsessionDefaultsProfiles:\n  unit:\n    projectPath: './App.xcodeproj'\n    scheme: 'App'\nactiveSessionDefaultsProfile: unit\n", to: ".mobilebuildmcp/config.yaml")
        var linked = FakeRunner()
        linked.linkWorktree(project, to: main)
        #expect(await ProjectConfigCheck().run(.fake(linked, project: project)) == .fail("no .mobilebuildmcp/config.yaml in this worktree: xcrew setup --worktree writes it from the main checkout's"))
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
        let legacy = await ProjectConfigCheck().run(.fake(project: project))
        #expect(legacy.status == .warn)
        #expect(legacy.message == ".xcodebuildmcp/ predates MobileBuildMCP 2.7.1 and is no longer read. It may be tracked in git, so it's the person's to agree to: rm -r '\(project.root.path)/.xcodebuildmcp'")
    }

    /// Before setup, a checkout whose generated project isn't there yet, as a fresh worktree's, hears of the generate too:
    /// setup alone leaves nothing to build.
    @Test(arguments: [(["Tuist.swift", "Project.swift"], "`tuist install && tuist generate --no-open`"), (["project.yml"], "`xcodegen generate`")])
    func beforeSetupAnUngeneratedProjectNamesTheGenerateToo(manifests: [String], generate: String) async {
        let project = Project.temporary()
        for manifest in manifests { project.write("", to: manifest) }
        let ungenerated = "the project isn't generated in this checkout yet either: run \(generate) from the project's root"
        #expect(await ProjectConfigCheck().run(.fake(project: project)) == .fail("no .mobilebuildmcp/config.yaml: run /xcrew:setup; \(ungenerated)"))
        let main = Project.temporary(containing: ["App.xcworkspace"])
        main.write("schemaVersion: 1\nsessionDefaultsProfiles:\n  unit:\n    workspacePath: './App.xcworkspace'\n    scheme: 'App'\nactiveSessionDefaultsProfile: unit\n", to: ".mobilebuildmcp/config.yaml")
        var linked = FakeRunner()
        linked.linkWorktree(project, to: main)
        #expect(await ProjectConfigCheck().run(.fake(linked, project: project)) == .fail("no .mobilebuildmcp/config.yaml in this worktree: xcrew setup --worktree writes it from the main checkout's; \(ungenerated)"))
        // Once generated, setup alone is said.
        project.write("", to: "App.xcworkspace/contents.xcworkspacedata")
        #expect(await ProjectConfigCheck().run(.fake(linked, project: project)) == .fail("no .mobilebuildmcp/config.yaml in this worktree: xcrew setup --worktree writes it from the main checkout's"))
    }

    /// A module's own project below the manifests isn't the app's workspace: the project still isn't generated.
    @Test func aModulesProjectIsntTheGeneratedWorkspace() async {
        let project = Project.temporary(containing: ["Modules/Core/Core.xcodeproj"])
        project.write("", to: "Tuist.swift")
        #expect(project.layout(.anywhereButHome).ungenerated?.path == "")
        project.write("", to: "App.xcworkspace/contents.xcworkspacedata")
        #expect(project.layout(.anywhereButHome).ungenerated == nil)
    }

    /// A config whose workspace isn't in this checkout, in a project a generator makes: the generated project is kept out
    /// of git, so a fresh worktree has none yet. The fix is the generate, not setup.
    @Test(arguments: [(["Tuist.swift", "Project.swift"], "`tuist install && tuist generate --no-open`"), (["project.yml"], "`xcodegen generate`")])
    func aGeneratedProjectNotYetGeneratedHereNamesTheGenerate(manifests: [String], generate: String) async {
        let project = Project.temporary()
        for manifest in manifests { project.write("", to: manifest) }
        project.write(ConfigRenderer.render(.init(container: "App.xcworkspace", testSimulator: "iPhone 17", testScheme: "App"), root: project.root), to: ".mobilebuildmcp/config.yaml")
        let result = await ProjectConfigCheck().run(.fake(project: project))
        #expect(result == .warn("the config points at App.xcworkspace, which isn't generated in this checkout yet: run \(generate) from the project's root"), "\(result.message)")
    }

    /// Without a generator, or with the workspace outside this checkout, the project moved or was renamed.
    @Test func aWorkspaceGoneFromAPlainProjectWasMoved() async {
        let project = Project.temporary(containing: ["Other.xcodeproj"])
        project.write(ConfigRenderer.render(.init(container: "App.xcworkspace", testSimulator: "iPhone 17", testScheme: "App"), root: project.root), to: ".mobilebuildmcp/config.yaml")
        #expect(await ProjectConfigCheck().run(.fake(project: project)) == .warn("the config points at App.xcworkspace, which no longer exists (the project moved or was renamed): xcrew setup"))
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
        let xcrews = "the config enables xcode-ide, MobileBuildMCP's second route to the Xcode MCP, whose answers Xcrew can't read: /xcrew:setup rewrites it"
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
        #expect(await ProjectConfigCheck().run(.fake(project: project)) == .warn("the config enables xcode-ide, MobileBuildMCP's second route to the Xcode MCP, whose answers Xcrew can't read: /xcrew:setup rewrites it (xcrew setup --force replaces it, as it changed after Xcrew wrote it)"))
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

    /// A relative path is the project root's, whatever folder the doctor runs from; an absolute one, as setup wrote up
    /// to 0.9.0, still counts as it is, and isn't outdated for that alone.
    @Test func containerPathsResolveFromTheProjectRoot() async {
        let project = Project.temporary(containing: ["A.xcworkspace"])
        func config(_ path: String) -> String {
            "schemaVersion: 1\nenabledWorkflows:\n  - simulator\nsessionDefaultsProfiles:\n  unit:\n    workspacePath: '\(path)'\n    scheme: 'A'\nactiveSessionDefaultsProfile: unit\n"
        }
        for path in ["./A.xcworkspace", "A.xcworkspace", "\(project.root.path)/A.xcworkspace"] {
            project.write(config(path), to: ".mobilebuildmcp/config.yaml")
            #expect(await ProjectConfigCheck().run(.fake(project: project)) == .pass(".mobilebuildmcp/config.yaml"), "\(path)")
        }
        project.write(config("./Gone.xcworkspace"), to: ".mobilebuildmcp/config.yaml")
        #expect(await ProjectConfigCheck().run(.fake(project: project)).message.hasPrefix("the config points at Gone.xcworkspace"))
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

    /// `simctl list runtimes` names each runtime's supported device types, so the fix is the exact create command.
    static let runtimes = #"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-4","version":"26.4","platform":"iOS","isAvailable":true,"supportedDeviceTypes":[{"name":"iPhone 16","identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-16"}]},{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-1","version":"27.1","platform":"iOS","isAvailable":true,"supportedDeviceTypes":[{"name":"iPhone 16","identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-16"},{"name":"iPhone 18","identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-18"}]}]}"#

    static func missingSimulator(_ name: String, in profile: String) -> (Project, FakeRunner) {
        let project = Project.temporary()
        let answers: ProfileAnswers = profile == "unit"
            ? .init(container: "A.xcworkspace", testSimulator: name, testScheme: "ATests")
            : .init(container: "A.xcworkspace", testSimulator: "iPhone 18", appSimulator: name, appScheme: "A", testScheme: "ATests")
        project.write(ConfigRenderer.render(answers, root: project.root), to: ".mobilebuildmcp/config.yaml")
        let devices = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-1":[{"name":"iPhone 18","udid":"U18","isAvailable":true}]}}"#
        return (project, FakeRunner(responses: ["xcrun simctl list devices available --json": .init(status: 0, stdout: devices), "xcrun simctl list runtimes --json": .init(status: 0, stdout: runtimes)]))
    }

    /// The fix for a missing simulator is to create it, with the newest runtime that supports it, or to pick an installed
    /// one with the option for the profile that names it; never a bare rerun, which drops the name the person chose.
    @Test func aMissingSimulatorNamesItsCreateCommandAndTheInstalledOnes() async {
        let (project, runner) = Self.missingSimulator("iPhone 16", in: "app")
        #expect(await SimulatorsCheck().run(.fake(runner, project: project)) == .warn("missing: iPhone 16: create it with xcrun simctl create \"iPhone 16\" com.apple.CoreSimulator.SimDeviceType.iPhone-16 com.apple.CoreSimulator.SimRuntime.iOS-27-1, or use an installed one with xcrew setup --app-simulator <name> (installed iPhones: iPhone 18)"))
    }

    @Test func aMissingSimulatorNoRuntimeSupportsIsOnlyReplaced() async {
        let (project, runner) = Self.missingSimulator("iPhone 9", in: "unit")
        #expect(await SimulatorsCheck().run(.fake(runner, project: project)) == .warn("missing: iPhone 9: no installed runtime supports it, so use an installed one with xcrew setup --test-simulator <name> (installed iPhones: iPhone 18)"))
    }

    @Test func aSimulatorIDThatIsGoneWarns() async {
        let project = Project.temporary()
        project.write(ConfigRenderer.render(.init(container: "A.xcworkspace", testSimulator: "iPhone 17", testScheme: "A"), root: project.root, simulatorIDs: ["iPhone 17": "GONE"]), to: ".mobilebuildmcp/config.yaml")
        let json = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone 17","udid":"NEW","isAvailable":true}]}}"#
        let runner = FakeRunner(responses: ["xcrun simctl list devices available --json": .init(status: 0, stdout: json)])
        #expect(await SimulatorsCheck().run(.fake(runner, project: project)) == .warn("a simulator the profiles name by ID is gone (GONE): xcrew setup writes the current ones"))
    }

    /// `xcrew setup --worktree` names a worktree's own simulators by ID alone: the check resolves each, as it does a name,
    /// and fails when one is gone, since MobileBuildMCP then has no simulator to run on.
    static let idOnly = "schemaVersion: 1\nsessionDefaultsProfiles:\n  unit:\n    workspacePath: 'A.xcworkspace'\n    scheme: 'A'\n    simulatorId: 'CLONE-1'\nactiveSessionDefaultsProfile: unit\n"

    @Test func aSimulatorNamedByIDAloneIsChecked() async {
        let project = Project.temporary()
        project.write(Self.idOnly, to: ".mobilebuildmcp/config.yaml")
        let json = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-2":[{"name":"xcrew · App · feature","udid":"CLONE-1","isAvailable":true}]}}"#
        let runner = FakeRunner(responses: ["xcrun simctl list devices available --json": .init(status: 0, stdout: json)])
        #expect(await SimulatorsCheck().run(.fake(runner, project: project)) == .pass("xcrew · App · feature (CLONE-1)"))
    }

    @Test func aSimulatorNamedByIDAloneThatIsGoneFails() async {
        let project = Project.temporary()
        project.write(Self.idOnly, to: ".mobilebuildmcp/config.yaml")
        let json = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-2":[{"name":"iPhone 18 Pro","udid":"OTHER","isAvailable":true}]}}"#
        let runner = FakeRunner(responses: ["xcrun simctl list devices available --json": .init(status: 0, stdout: json)])
        #expect(await SimulatorsCheck().run(.fake(runner, project: project)) == .fail("a simulator the profiles name by ID alone is gone (CLONE-1), so MobileBuildMCP has none to run on: xcrew setup --worktree makes the worktree's own again"))
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
        try FileManager.default.setAttributes([.modificationDate: Self.now.addingTimeInterval(-seconds)], ofItemAtPath: project.managedMarker.path)
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
        #expect(await ConfigLoadedCheck().run(.fake(runner, project: project, processID: 300, now: Self.now)).status == .pass)
    }

    @Test func aConfigNewerThanThisSessionsServerAsksForARestart() async throws {
        let project = Project.temporary()
        let runner = try sessions(project: project, mine: "05:00", theirs: "00:30", configAgo: 60)
        #expect(await ConfigLoadedCheck().run(.fake(runner, project: project, processID: 300, now: Self.now)) == .warn("the config changed after this session's MobileBuildMCP started: restart Claude Code to load it"))
    }

    /// The server's start is the machine's time less how long it has run: a config written a minute before the machine's
    /// time is newer than a server running five minutes.
    @Test func aServersStartIsTheMachinesTimeLessItsAge() async throws {
        let project = Project.temporary()
        let runner = try sessions(project: project, mine: "05:00", theirs: "00:30", configAgo: 0)
        let written = Date(timeIntervalSince1970: 1_767_225_600)
        try FileManager.default.setAttributes([.modificationDate: written], ofItemAtPath: project.managedMarker.path)
        let result = await ConfigLoadedCheck().run(.fake(runner, project: project, processID: 300, now: written.addingTimeInterval(60)))
        #expect(result == .warn("the config changed after this session's MobileBuildMCP started: restart Claude Code to load it"))
    }

    /// From a terminal there's no session to match, so the oldest server for the project stands for any stale one.
    @Test func fromATerminalTheOldestServerCounts() async throws {
        let project = Project.temporary()
        let runner = try sessions(project: project, mine: "00:30", theirs: "1-02:10:00", configAgo: 60)
        #expect(await ConfigLoadedCheck().run(.fake(runner, project: project, processID: 600, now: Self.now)) == .warn("a MobileBuildMCP serving this project started before the config changed: restart its Claude Code session to load it"))
    }

    /// Setup changed only profiles since the server started: `session_set_defaults` applies them, no restart.
    @Test func profilesChangedSinceTheServerStartedAskForNoRestart() async throws {
        let project = Project.temporary()
        let runner = try sessions(project: project, mine: "05:00", theirs: "00:30", configAgo: 60)
        project.write("", to: ".mobilebuildmcp/.xcrew-server")
        try FileManager.default.setAttributes([.modificationDate: Self.now.addingTimeInterval(-86_400)], ofItemAtPath: project.serverMarker.path)
        #expect(await ConfigLoadedCheck().run(.fake(runner, project: project, processID: 300, now: Self.now)) == .pass("loaded at its start; the profiles written since come through session_set_defaults, as setup printed"))
    }

    /// The tool groups or another server setting changed since: only a restart loads those, though builds go on.
    @Test func serverSettingsChangedSinceTheServerStartedAskForARestart() async throws {
        let project = Project.temporary()
        let runner = try sessions(project: project, mine: "05:00", theirs: "00:30", configAgo: 60)
        project.write("", to: ".mobilebuildmcp/.xcrew-server")
        try FileManager.default.setAttributes([.modificationDate: Self.now.addingTimeInterval(-60)], ofItemAtPath: project.serverMarker.path)
        #expect(await ConfigLoadedCheck().run(.fake(runner, project: project, processID: 300, now: Self.now)) == .warn("the config's tool groups or server settings changed after this session's MobileBuildMCP started: builds and tests go on, and restarting Claude Code loads the rest"))
    }

    /// MobileBuildMCP saves session defaults with `persist: true` into its own config, which it already holds.
    @Test func theServersOwnWriteAsksForNoRestart() async throws {
        let project = Project.temporary()
        let runner = try sessions(project: project, mine: "00:30", theirs: "10:00", configAgo: 60)
        project.write("schemaVersion: 1\nactiveSessionDefaultsProfile: app\n", to: ".mobilebuildmcp/config.yaml")
        #expect(await ConfigLoadedCheck().run(.fake(runner, project: project, processID: 300, now: Self.now)).status == .pass)
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
        try FileManager.default.setAttributes([.modificationDate: Self.now.addingTimeInterval(-60)], ofItemAtPath: project.managedMarker.path)
        let claude = "/Users/me/Library/Application Support/Claude/claude-code/1.0/claude"
        let ps = "  100 1 01:00:00 \(claude) --resume\n  200 100 05:00 \(Self.server)\n  300 100 00:01 /plugins/xcrew/.build/xcrew doctor\n  400 1 01:00:00 claude\n  500 400 10:00 \(Self.server)\n"
        let comm = "  100 \(claude)\n  200 /opt/homebrew/Cellar/mobilebuildmcp/2.7.1/libexec/node-runtime\n  300 /plugins/xcrew/.build/xcrew\n  400 /Users/me/.local/bin/claude\n  500 /opt/homebrew/Cellar/mobilebuildmcp/2.7.1/libexec/node-runtime\n"
        #expect(await ConfigLoadedCheck().run(.fake(runner(ps: ps, comm: comm, cwd: [200, 500], project: project), project: project, processID: 300, now: Self.now)) == .warn("the config changed after this session's MobileBuildMCP started: restart Claude Code to load it"))
    }

    /// A server whose Claude Code exited is adopted by launchd; no session owns it, so no restart reaches it.
    @Test func anOrphanedServerIsNobodysToRestart() async throws {
        let project = Project.temporary()
        project.write("", to: ".mobilebuildmcp/.xcrew-managed")
        try FileManager.default.setAttributes([.modificationDate: Self.now.addingTimeInterval(-60)], ofItemAtPath: project.managedMarker.path)
        let ps = "  400 1 01:00:00 claude\n  500 400 00:30 \(Self.server)\n  700 1 10:00 \(Self.server)\n  600 1 00:01 /plugins/xcrew/.build/xcrew doctor\n"
        let comm = "  400 claude\n  500 node-runtime\n  700 node-runtime\n  600 xcrew\n"
        #expect(await ConfigLoadedCheck().run(.fake(runner(ps: ps, comm: comm, cwd: [500, 700], project: project), project: project, processID: 600, now: Self.now)).status == .pass)
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

    /// Headless Xcode MCP came with Xcode 27: on a Mac whose newest Xcode is older, it's not there to turn on.
    @Test func belowXcode27HeadlessXcodeMCPSkips() async {
        let project = Project.temporary()
        let apps = project.root.appending(path: "Applications")
        FakeXcode.install(in: apps, "Xcode-26.6.app", version: "26.6", build: "17G100")
        FakeXcode.install(in: apps, "Xcode-26.5.app", version: "26.5", build: "17F100")
        let context = CheckContext.fake(project: project, applications: apps)
        #expect(await HeadlessXcodeMCPCheck().run(context) == .skip("available with Xcode 27 or later"))
        #expect(await ClaudeApprovedCheck().run(context) == .skip("available with Xcode 27 or later"))
    }

    /// An Xcode whose version can't be read could be 27 or later, so it doesn't make the Mac too old.
    @Test func anXcodeOfUnknownVersionDoesntPredateHeadlessXcodeMCP() async {
        let project = Project.temporary()
        let apps = project.root.appending(path: "Applications")
        FakeXcode.install(in: apps, "Xcode-26.6.app", version: "26.6", build: "17G100")
        FakeXcode.install(in: apps, "Xcode-Next.app", version: "", build: nil)
        #expect(await HeadlessXcodeMCPCheck().run(.fake(project: project, applications: apps)).status == .fail)
    }

    /// Selecting an older Xcode may be deliberate: the line names the switch rather than failing.
    @Test func withXcode27InstalledButAnOlderSelectedTheSwitchIsNamed() async {
        let project = Project.temporary()
        let apps = project.root.appending(path: "Applications")
        FakeXcode.installBoth(in: apps)
        let runner = FakeRunner(responses: ["xcode-select -p": .init(status: 0, stdout: "\(apps.path)/Xcode-26.4.app/Contents/Developer\n")])
        let context = CheckContext.fake(runner, project: project, applications: apps)
        for result in [await HeadlessXcodeMCPCheck().run(context), await ClaudeApprovedCheck().run(context)] {
            #expect(result.status == .skip)
            #expect(result.message.hasPrefix("Xcode 27.2 is installed: `sudo xcode-select -s /"))
            #expect(result.message.hasSuffix("/Applications/Xcode-27.2.0-Beta.3.app` turns on headless Xcode MCP"))
        }
    }

    /// With Xcode 27 installed, a server that doesn't answer is a real problem.
    @Test func withXcode27AnUnavailableXcodeMCPStillFails() async {
        let project = Project.temporary()
        let apps = project.root.appending(path: "Applications")
        FakeXcode.installBoth(in: apps)
        let context = CheckContext.fake(project: project, applications: apps)
        #expect(await HeadlessXcodeMCPCheck().run(context) == .fail("xcrun mcp-server unavailable (needs Xcode 27 or later)"))
        #expect(await ClaudeApprovedCheck().run(context) == .skip("xcrun mcp-server unavailable"))
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

        func run(_ argv: [String], stdin: Data?) async -> CommandResult {
            if argv == ["xcrun", "mcp-server", "status"] { lock.withLock { statuses += 1 } }
            return CommandResult(status: 0, stdout: "Permission: enabled\ncom.anthropic.claude-code")
        }

        func which(_ name: String) -> String? { nil }
    }

    @Test func oneDoctorRunAsksTheXcodeMCPForItsStatusOnce() async {
        let runner = CountingRunner()
        let project = Project.temporary()
        let context = CheckContext(project: project, machine: Machine(environment: [:], home: project.root, runner: runner, applications: project.root.appending(path: "Applications"), files: RootedFiles(roots: [project.root])))
        let entries = await Doctor.run(Doctor.checks.filter { $0.id.hasPrefix("xcode-mcp/headless") || $0.id.hasPrefix("xcode-mcp/claude") }, in: context)
        #expect(entries.map(\.result.status) == [.pass, .pass])
        #expect(runner.statusCalls == 1)
    }
}
