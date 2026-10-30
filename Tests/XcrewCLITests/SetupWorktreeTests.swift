import Foundation
import Testing
@testable import XcrewCLI
@testable import XcrewCore
import XcrewTestSupport

/// `xcrew setup --worktree`: a linked worktree's MobileBuildMCP config, taken from its main checkout's.
@Suite struct SetupWorktreeTests {
    /// The main checkout's config: a profile with an absolute DerivedData, outside the checkout, and one written from
    /// the root.
    static let mainConfig = """
        schemaVersion: 1
        sessionDefaultsProfiles:
          unit:
            projectPath: 'App.xcodeproj'
            scheme: 'App'
            derivedDataPath: '/Users/someone/DerivedData/App'
        activeSessionDefaultsProfile: unit

        """

    /// A worktree whose git says its main checkout is `main`, or a main checkout when `main` is nil.
    static func worktree(main: Project?) -> (Project, CheckContext) {
        let worktree = Project.temporary(containing: ["App.xcodeproj"])
        var runner = FakeRunner()
        if let main { runner.linkWorktree(worktree, to: main) } else {
            runner.responses["git -C \(worktree.root.path) rev-parse --path-format=absolute --git-dir --git-common-dir --show-prefix"] = CommandResult(status: 0, stdout: "\(worktree.root.path)/.git\n\(worktree.root.path)/.git\n\n")
        }
        return (worktree, .fake(runner, project: worktree))
    }

    static func config(_ project: Project) -> String? {
        try? String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8)
    }

    @Test func aWorktreeTakesTheMainCheckoutsConfig() async {
        let main = Project.temporary(containing: ["App.xcodeproj"])
        main.write(Self.mainConfig, to: ".mobilebuildmcp/config.yaml")
        let (worktree, context) = Self.worktree(main: main)
        let run = await Run("setup", "--worktree", context: context)
        #expect(run.status == 0)
        #expect(Self.config(worktree) == Self.mainConfig.replacingOccurrences(of: "    derivedDataPath: '/Users/someone/DerivedData/App'\n", with: ""))
        #expect(run.output == [
            "xcrew: wrote .mobilebuildmcp/config.yaml from the main checkout's (\(main.root.path)); restart Claude Code so MobileBuildMCP reads it",
            "xcrew: left out derivedDataPath /Users/someone/DerivedData/App, which the main checkout uses: this worktree's builds go in a DerivedData of its own",
        ])
        // xcrew wrote it: a later setup may replace it, and the doctor asks for a restart.
        #expect(ConfigWriter.keeping(worktree) == nil)
    }

    /// Like setup, it keeps `.mobilebuildmcp/` out of git, in the exclude file every worktree of the repository shares.
    @Test func theConfigIsKeptOutOfGit() async {
        let main = Project.temporary(containing: ["App.xcodeproj"])
        main.write(Self.mainConfig, to: ".mobilebuildmcp/config.yaml")
        main.write("", to: ".git/info/exclude")
        let worktree = Project.temporary(containing: ["App.xcodeproj"])
        var runner = FakeRunner(responses: ["git -C \(worktree.root.path) rev-parse --git-path info/exclude": CommandResult(status: 0, stdout: "\(main.root.path)/.git/info/exclude\n")])
        runner.linkWorktree(worktree, to: main)
        let run = await Run("setup", "--worktree", context: .fake(runner, project: worktree))
        #expect(run.output.last == "xcrew: kept .mobilebuildmcp/ out of git (in .git/info/exclude, which isn't committed)", "\(run.output)")
        #expect((try? String(contentsOf: main.root.appending(path: ".git/info/exclude"), encoding: .utf8)) == "/.mobilebuildmcp/\n")
    }

    @Test func aWorktreeConfigEditedSinceIsKept() async {
        let main = Project.temporary(containing: ["App.xcodeproj"])
        main.write(Self.mainConfig, to: ".mobilebuildmcp/config.yaml")
        let (worktree, context) = Self.worktree(main: main)
        _ = await Run("setup", "--worktree", context: context)
        worktree.write("schemaVersion: 1\n# mine\n", to: ".mobilebuildmcp/config.yaml")
        let run = await Run("setup", "--worktree", context: context)
        #expect(Self.config(worktree) == "schemaVersion: 1\n# mine\n")
        #expect(run.output == ["xcrew: .mobilebuildmcp/config.yaml was edited after xcrew wrote it; left as is (--force replaces it, keeping a backup)"])
    }

    @Test func theMainCheckoutWithoutAConfigIsSaidSo() async {
        let main = Project.temporary(containing: ["App.xcodeproj"])
        let (_, context) = Self.worktree(main: main)
        let run = await Run("setup", "--worktree", context: context)
        #expect(run.status == 1)
        #expect(run.output == ["xcrew: the main checkout (\(main.root.path)) has no .mobilebuildmcp/config.yaml; xcrew setup there, or plain xcrew setup here, writes one"])
    }

    /// Its config is the main checkout's, so the options that answer setup's questions have no place beside it.
    @Test func anotherOptionIsAUsageError() async {
        let main = Project.temporary(containing: ["App.xcodeproj"])
        main.write(Self.mainConfig, to: ".mobilebuildmcp/config.yaml")
        let (worktree, context) = Self.worktree(main: main)
        let run = await Run("setup", "--worktree", "--test-scheme", "AppTests", context: context)
        #expect(run.status == 64)
        #expect(run.errors == ["setup --worktree takes no option but --force, --no-simulator and --fresh-simulator: the profiles are the main checkout's"])
        #expect(Self.config(worktree) == nil)
    }

    @Test func outsideAWorktreeItIsAUsageError() async {
        let (_, context) = Self.worktree(main: nil)
        let run = await Run("setup", "--worktree", context: context)
        #expect(run.status == 64)
        #expect(run.errors == ["setup --worktree runs in a linked git worktree; this is a main checkout, or not in git"])
    }

    // MARK: A simulator of the worktree's own

    /// The main checkout's config, its profile naming the simulator its runs use.
    static let mainWithSimulator = mainConfig.replacingOccurrences(of: "    scheme: 'App'\n", with: "    scheme: 'App'\n    simulatorName: 'iPhone 18 Pro'\n")
    static let iPhone18Pro = "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"
    static let iOS272 = "com.apple.CoreSimulator.SimRuntime.iOS-27-2"

    /// `simctl list devices available --json` on a Mac with `devices`, by name and udid, iPhone 18 Pros on iOS 27.2 unless
    /// another type or runtime is given, each in `state`: booted unless said, so a simulator is created, not cloned.
    static func listed(_ devices: [(name: String, udid: String)], more: [(name: String, udid: String, type: String, runtime: String)] = [], state: String = "Booted") -> String {
        let all = devices.map { ($0.name, $0.udid, iPhone18Pro, iOS272) } + more.map { ($0.name, $0.udid, $0.type, $0.runtime) }
        let byRuntime = Dictionary(grouping: all) { $0.3 }
        let runtimes = byRuntime.keys.sorted().map { runtime in
            let entries = (byRuntime[runtime] ?? []).map { #"{"name":"\#($0.0)","udid":"\#($0.1)","isAvailable":true,"state":"\#(state)","deviceTypeIdentifier":"\#($0.2)"}"# }
            return #""\#(runtime)":[\#(entries.joined(separator: ","))]"#
        }
        return #"{"devices":{\#(runtimes.joined(separator: ","))}}"#
    }

    /// A worktree of a main checkout whose config names its simulator, on a Mac with `devices`, where `simctl create`
    /// answers `created`.
    static func withSimulator(devices: [(name: String, udid: String)] = [("iPhone 18 Pro", "MAIN-UDID")], created: String = "NEW-UDID") -> (main: Project, worktree: Project, context: CheckContext, name: String) {
        let main = Project.temporary(containing: ["App.xcodeproj"])
        main.write(mainWithSimulator, to: ".mobilebuildmcp/config.yaml")
        let worktree = Project.temporary(containing: ["App.xcodeproj"])
        let name = "xcrew · \(main.root.lastPathComponent) · \(worktree.root.lastPathComponent)"
        var runner = FakeRunner(responses: [
            "xcrun simctl list devices available --json": CommandResult(status: 0, stdout: listed(devices)),
            "xcrun simctl create \(name) \(iPhone18Pro) \(iOS272)": CommandResult(status: 0, stdout: "\(created)\n"),
        ])
        runner.linkWorktree(worktree, to: main)
        return (main, worktree, .fake(runner, project: worktree), name)
    }

    /// The worktree gets a simulator of its own, on the main checkout's device type and runtime, said plainly, and its
    /// profile names it by id.
    @Test func aWorktreeGetsASimulatorOfItsOwn() async {
        let (_, worktree, context, name) = Self.withSimulator()
        let run = await Run("setup", "--worktree", context: context)
        #expect(run.status == 0)
        #expect(run.output.contains { $0.hasPrefix("xcrew: created simulator `\(name)` (iPhone 18 Pro, iOS 27.2) fresh for this worktree") }, "\(run.output)")
        #expect(Self.config(worktree)?.contains("    simulatorId: 'NEW-UDID'\n") == true)
        #expect(Self.config(worktree)?.contains("simulatorName") == false)
    }

    /// One made for this worktree before is used again, never doubled.
    @Test func aSimulatorMadeForTheWorktreeBeforeIsUsedAgain() async {
        let (_, worktree, context, name) = Self.withSimulator()
        var runner = context.runner as? FakeRunner ?? FakeRunner()
        runner.responses["xcrun simctl list devices available --json"] = CommandResult(status: 0, stdout: Self.listed([("iPhone 18 Pro", "MAIN-UDID"), (name, "EARLIER-UDID")]))
        runner.responses["xcrun simctl create \(name) \(Self.iPhone18Pro) \(Self.iOS272)"] = nil
        let run = await Run("setup", "--worktree", context: .fake(runner, project: worktree))
        #expect(run.output.contains("xcrew: this worktree uses simulator `\(name)` (iPhone 18 Pro, iOS 27.2), made for it earlier"), "\(run.output)")
        #expect(Self.config(worktree)?.contains("    simulatorId: 'EARLIER-UDID'\n") == true)
    }

    /// `--no-simulator` shares the main checkout's simulator: nothing is made, and the profile names it as before.
    @Test func noSimulatorSharesTheMainCheckouts() async {
        let (_, worktree, context, _) = Self.withSimulator()
        let run = await Run("setup", "--worktree", "--no-simulator", context: context)
        #expect(run.status == 0)
        #expect(!run.output.contains { $0.contains("simulator `") })
        #expect(Self.config(worktree)?.contains("    simulatorName: 'iPhone 18 Pro'\n") == true)
    }

    /// A simulator the main checkout names that this Mac doesn't have: nothing is made, and setup says why.
    @Test func aMainSimulatorThisMacLacksMakesNone() async {
        let (_, worktree, context, _) = Self.withSimulator(devices: [])
        let run = await Run("setup", "--worktree", context: context)
        #expect(run.output.contains("xcrew: the main checkout's simulator, iPhone 18 Pro, isn't on this Mac, so none was made for it in this worktree; its profile names that one"), "\(run.output)")
        #expect(Self.config(worktree)?.contains("    simulatorName: 'iPhone 18 Pro'\n") == true)
    }

    /// A main checkout set up by plain setup names its simulator twice, by name and by id: the worktree's profile names
    /// its own once, as one key.
    @Test func aSimulatorNamedTwiceIsNamedOnce() async {
        let (main, worktree, context, name) = Self.withSimulator()
        main.write(Self.mainWithSimulator.replacingOccurrences(of: "    simulatorName: 'iPhone 18 Pro'\n", with: "    simulatorName: 'iPhone 18 Pro'\n    simulatorId: 'MAIN-UDID'\n") + "sessionDefaults:\n  simulatorName: 'iPhone 18 Pro'\n  simulatorId: 'MAIN-UDID'\n", to: ".mobilebuildmcp/config.yaml")
        let run = await Run("setup", "--worktree", context: context)
        #expect(run.output.contains { $0.hasPrefix("xcrew: created simulator `\(name)` (iPhone 18 Pro, iOS 27.2) fresh for this worktree") }, "\(run.output)")
        let written = Self.config(worktree) ?? ""
        #expect(written.components(separatedBy: "simulatorId: 'NEW-UDID'").count - 1 == 2, "\(written)")
        #expect(!written.contains("simulatorName") && !written.contains("MAIN-UDID"), "\(written)")
    }

    /// The id says which runtime when one name is on two: the worktree's is made on the runtime the id is on, not the
    /// first the name finds.
    @Test func theIdSaysWhichRuntime() async {
        let (main, worktree, _, name) = Self.withSimulator()
        main.write(Self.mainWithSimulator.replacingOccurrences(of: "    simulatorName: 'iPhone 18 Pro'\n", with: "    simulatorName: 'iPhone 18 Pro'\n    simulatorId: 'MAIN-UDID'\n"), to: ".mobilebuildmcp/config.yaml")
        let iOS265 = "com.apple.CoreSimulator.SimRuntime.iOS-26-5"
        var runner = FakeRunner(responses: [
            "xcrun simctl list devices available --json": CommandResult(status: 0, stdout: Self.listed([("iPhone 18 Pro", "MAIN-UDID")], more: [("iPhone 18 Pro", "EARLY-UDID", Self.iPhone18Pro, iOS265)])),
            "xcrun simctl create \(name) \(Self.iPhone18Pro) \(Self.iOS272)": CommandResult(status: 0, stdout: "NEW-UDID\n"),
        ])
        runner.linkWorktree(worktree, to: main)
        let run = await Run("setup", "--worktree", context: .fake(runner, project: worktree))
        #expect(run.output.contains { $0.hasPrefix("xcrew: created simulator `\(name)` (iPhone 18 Pro, iOS 27.2) fresh for this worktree") }, "\(run.output)")
    }

    /// Profiles that run on different simulators each get one of their own, named by device type.
    @Test func eachSimulatorTheProfilesUseGetsItsOwn() async {
        let (main, worktree, _, name) = Self.withSimulator()
        let iPad = "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch"
        main.write(Self.mainWithSimulator.replacingOccurrences(of: "activeSessionDefaultsProfile: unit\n", with: "  app:\n    scheme: 'App'\n    simulatorName: 'iPad Pro 13-inch'\nactiveSessionDefaultsProfile: unit\n"), to: ".mobilebuildmcp/config.yaml")
        var runner = FakeRunner(responses: [
            "xcrun simctl list devices available --json": CommandResult(status: 0, stdout: Self.listed([("iPhone 18 Pro", "MAIN-UDID")], more: [("iPad Pro 13-inch", "PAD-UDID", iPad, Self.iOS272)])),
            "xcrun simctl create \(name) · iPhone 18 Pro \(Self.iPhone18Pro) \(Self.iOS272)": CommandResult(status: 0, stdout: "PHONE-NEW\n"),
            "xcrun simctl create \(name) · iPad Pro 13 inch \(iPad) \(Self.iOS272)": CommandResult(status: 0, stdout: "PAD-NEW\n"),
        ])
        runner.linkWorktree(worktree, to: main)
        let run = await Run("setup", "--worktree", context: .fake(runner, project: worktree))
        #expect(run.output.contains { $0.hasPrefix("xcrew: created simulator `\(name) · iPad Pro 13 inch` (iPad Pro 13 inch, iOS 27.2) fresh for this worktree") }, "\(run.output)")
        let written = Self.config(worktree) ?? ""
        #expect(written.contains("simulatorId: 'PHONE-NEW'") && written.contains("simulatorId: 'PAD-NEW'"), "\(written)")
    }

    /// A project a folder down in its repository is named by its repository's folders, so worktrees don't share one.
    @Test func aProjectInASubfolderIsNamedByItsRepositorys() async {
        let mainTop = Project.temporary(containing: ["ios/App.xcodeproj"]), worktreeTop = Project.temporary(containing: ["ios/App.xcodeproj"])
        let main = Project(root: mainTop.root.appending(path: "ios")), worktree = Project(root: worktreeTop.root.appending(path: "ios"))
        main.write(Self.mainWithSimulator, to: ".mobilebuildmcp/config.yaml")
        let name = "xcrew · \(mainTop.root.lastPathComponent) · \(worktreeTop.root.lastPathComponent)"
        let runner = FakeRunner(responses: [
            "git -C \(worktree.root.path) rev-parse --path-format=absolute --git-dir --git-common-dir --show-prefix": CommandResult(status: 0, stdout: "\(mainTop.root.path)/.git/worktrees/wt\n\(mainTop.root.path)/.git\nios/\n"),
            "git -C \(worktree.root.path) worktree list --porcelain": CommandResult(status: 0, stdout: "worktree \(mainTop.root.path)\nHEAD 0\nbranch refs/heads/main\n\nworktree \(worktreeTop.root.path)\nHEAD 0\nbranch refs/heads/wt\n\n"),
            "xcrun simctl list devices available --json": CommandResult(status: 0, stdout: Self.listed([("iPhone 18 Pro", "MAIN-UDID")])),
            "xcrun simctl create \(name) \(Self.iPhone18Pro) \(Self.iOS272)": CommandResult(status: 0, stdout: "NEW-UDID\n"),
        ])
        let run = await Run("setup", "--worktree", context: .fake(runner, project: worktree))
        #expect(run.output.contains { $0.hasPrefix("xcrew: created simulator `\(name)` (iPhone 18 Pro, iOS 27.2) fresh for this worktree") }, "\(run.output)")
    }

    /// `--no-simulator` belongs to a worktree's setup alone.
    @Test func noSimulatorWithoutWorktreeIsAUsageError() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        #expect(await Run("setup", "--no-simulator", context: .fake(project: project)).errors == ["setup --no-simulator goes with --worktree: plain setup makes no simulator"])
    }

    // MARK: Cloned when it can be

    /// A worktree of a main checkout whose simulator is shut down, where `simctl clone` answers `CLONE-UDID`.
    static func withShutDownSimulator() -> (worktree: Project, runner: FakeRunner, name: String) {
        let (_, worktree, context, name) = withSimulator()
        var runner = context.runner as? FakeRunner ?? FakeRunner()
        runner.responses["xcrun simctl list devices available --json"] = CommandResult(status: 0, stdout: listed([("iPhone 18 Pro", "MAIN-UDID")], state: "Shutdown"))
        runner.responses["xcrun simctl clone MAIN-UDID \(name)"] = CommandResult(status: 0, stdout: "CLONE-UDID\n")
        return (worktree, runner, name)
    }

    /// A shut-down main simulator is cloned: settled already, and bringing the main checkout's apps and data, as setup says.
    @Test func aShutDownMainSimulatorIsCloned() async {
        let (worktree, runner, name) = Self.withShutDownSimulator()
        let run = await Run("setup", "--worktree", context: .fake(runner, project: worktree))
        #expect(run.output.contains("xcrew: cloned simulator `\(name)` (iPhone 18 Pro, iOS 27.2) from iPhone 18 Pro, with its apps and data, for this worktree"), "\(run.output)")
        #expect(Self.config(worktree)?.contains("    simulatorId: 'CLONE-UDID'\n") == true)
    }

    /// A booted main simulator can't be cloned: one is made fresh, and setup says why.
    @Test func aBootedMainSimulatorIsMadeFresh() async {
        let (_, _, context, name) = Self.withSimulator()
        let run = await Run("setup", "--worktree", context: context)
        #expect(run.output.contains("xcrew: created simulator `\(name)` (iPhone 18 Pro, iOS 27.2) fresh for this worktree: iPhone 18 Pro is booted, and only a shut-down simulator can be cloned"), "\(run.output)")
    }

    /// `--fresh-simulator` makes a clean device even when the main one could be cloned.
    @Test func freshSimulatorAlwaysCreates() async {
        let (worktree, runner, name) = Self.withShutDownSimulator()
        let run = await Run("setup", "--worktree", "--fresh-simulator", context: .fake(runner, project: worktree))
        #expect(run.output.contains("xcrew: created simulator `\(name)` (iPhone 18 Pro, iOS 27.2) for this worktree"), "\(run.output)")
        #expect(Self.config(worktree)?.contains("    simulatorId: 'NEW-UDID'\n") == true)
    }

    /// A clone that fails falls back to a fresh one, saying why.
    @Test func aFailedCloneFallsBackToAFreshOne() async {
        let (worktree, shutDown, name) = Self.withShutDownSimulator()
        var runner = shutDown
        runner.responses["xcrun simctl clone MAIN-UDID \(name)"] = CommandResult(status: 1, stdout: "", stderr: "Unable to clone device.\n")
        let run = await Run("setup", "--worktree", context: .fake(runner, project: worktree))
        #expect(run.output.contains("xcrew: created simulator `\(name)` (iPhone 18 Pro, iOS 27.2) fresh for this worktree: cloning iPhone 18 Pro failed (Unable to clone device.)"), "\(run.output)")
        #expect(Self.config(worktree)?.contains("    simulatorId: 'NEW-UDID'\n") == true)
    }

    /// One made earlier stays the worktree's: `--fresh-simulator` says how to start clean rather than make a twin.
    @Test func freshSimulatorKeepsOneMadeEarlierAndSaysHowToStartClean() async {
        let (worktree, shutDown, name) = Self.withShutDownSimulator()
        var runner = shutDown
        runner.responses["xcrun simctl list devices available --json"] = CommandResult(status: 0, stdout: Self.listed([("iPhone 18 Pro", "MAIN-UDID"), (name, "EARLIER-UDID")], state: "Shutdown"))
        let run = await Run("setup", "--worktree", "--fresh-simulator", context: .fake(runner, project: worktree))
        #expect(run.output.contains("xcrew: this worktree uses simulator `\(name)` (iPhone 18 Pro, iOS 27.2), made for it earlier; `xcrun simctl delete EARLIER-UDID` and setup again make a fresh one"), "\(run.output)")
    }

    /// Sharing the main checkout's simulator and making a fresh one can't both be.
    @Test func noSimulatorAndFreshSimulatorTogetherAreAUsageError() async {
        let (_, _, context, _) = Self.withSimulator()
        let run = await Run("setup", "--worktree", "--no-simulator", "--fresh-simulator", context: context)
        #expect(run.status == 64)
        #expect(run.errors == ["setup --worktree takes --no-simulator or --fresh-simulator, not both"])
    }

    @Test func freshSimulatorWithoutWorktreeIsAUsageError() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        #expect(await Run("setup", "--fresh-simulator", context: .fake(project: project)).errors == ["setup --fresh-simulator goes with --worktree: plain setup makes no simulator"])
    }

    /// A main simulator neither shut down nor booted, as one still shutting down, is said as it is.
    @Test func aMainSimulatorShuttingDownIsSaidAsItIs() async {
        let (worktree, shutDown, name) = Self.withShutDownSimulator()
        var runner = shutDown
        runner.responses["xcrun simctl list devices available --json"] = CommandResult(status: 0, stdout: Self.listed([("iPhone 18 Pro", "MAIN-UDID")], state: "Shutting Down"))
        let run = await Run("setup", "--worktree", context: .fake(runner, project: worktree))
        #expect(run.output.contains("xcrew: created simulator `\(name)` (iPhone 18 Pro, iOS 27.2) fresh for this worktree: iPhone 18 Pro isn't shut down (Shutting Down), and only a shut-down simulator can be cloned"), "\(run.output)")
    }
}
