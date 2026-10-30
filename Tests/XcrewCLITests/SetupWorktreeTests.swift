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
        #expect(run.errors == ["setup --worktree takes no option but --force and --no-simulator: the profiles are the main checkout's"])
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

    /// `simctl list devices available --json` on a Mac with `devices`, by name and udid, all iPhone 18 Pros on iOS 27.2.
    static func listed(_ devices: [(name: String, udid: String)]) -> String {
        let entries = devices.map { #"{"name":"\#($0.name)","udid":"\#($0.udid)","isAvailable":true,"state":"Shutdown","deviceTypeIdentifier":"\#(iPhone18Pro)"}"# }
        return #"{"devices":{"\#(iOS272)":[\#(entries.joined(separator: ","))]}}"#
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
        #expect(run.output.contains("xcrew: created simulator `\(name)` (iPhone 18 Pro, iOS 27.2) for this worktree"), "\(run.output)")
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
        #expect(run.output.contains("xcrew: the main checkout's simulator, iPhone 18 Pro, isn't on this Mac, so none was made for this worktree; its profile names that one"), "\(run.output)")
        #expect(Self.config(worktree)?.contains("    simulatorName: 'iPhone 18 Pro'\n") == true)
    }
}
