import Foundation
import Testing
import XcrewTestSupport

@testable import XcrewCore

/// The doctor's simulator upkeep: what `setup --worktree` left behind, and what the booted ones take of the Mac's memory.
@Suite struct SimulatorChecksTests {
    /// `simctl list devices --json` with these devices on iOS 27.2, each `(name, udid, state, isAvailable)`.
    static func devices(_ devices: [(String, String, String, Bool)]) -> CommandResult {
        FakeRunner.simctlDevices(devices.map { (name: $0.0, udid: $0.1, state: $0.2, isAvailable: $0.3) })
    }

    /// A main checkout with linked worktrees in `trees/`, `live` there on disk and listed by git, `prunable` listed with
    /// their folders gone, and setup's record of what it made, each simulator by udid and the worktree it names.
    static func leftovers(_ devices: [(String, String, String, Bool)], live: [String], prunable: [String] = [], recorded: [(udid: String, worktree: String)]) throws -> CheckContext {
        let main = Project.temporary(containing: live.map { "trees/\($0)" })
        let trees = main.root.appending(path: "trees")
        var record = WorktreeSimulatorRecord()
        for entry in recorded { record = record.adding(entry.udid, for: trees.appending(path: entry.worktree)) }
        try record.write(to: main.root.appending(path: ".git/xcrew/worktree-simulators"))
        let runner = FakeRunner(responses: [
            "xcrun simctl list devices --json": Self.devices(devices),
            "git -C \(main.root.path) rev-parse --path-format=absolute --git-common-dir": .init(status: 0, stdout: "\(main.root.path)/.git\n"),
            "git -C \(main.root.path) worktree list --porcelain": FakeRunner.worktreeList(
                main: main.root.path, linked: live.map { trees.appending(path: $0).path }, prunable: prunable.map { trees.appending(path: $0).path }
            ),
        ])
        return .fake(runner, project: main)
    }

    @Test func aRecordedSimulatorWhoseWorktreeIsGoneIsNamedWithItsDeleteCommand() async throws {
        let context = try Self.leftovers([("xcrew · App · old", "U1", "Shutdown", true), ("xcrew · App · live", "U2", "Shutdown", true)], live: ["live"], recorded: [("U1", "old"), ("U2", "live")])
        let result = await WorktreeLeftoversCheck().run(context)
        #expect(result == .warn("`xcrew · App · old` (its worktree is gone); `xcrun simctl delete U1` removes it"))
        #expect(result.isOffThePrompt == false)
    }

    /// git calls a worktree whose folder was deleted prunable: it's gone too.
    @Test func aPrunableWorktreeCountsAsGone() async throws {
        let context = try Self.leftovers([("xcrew · App · moved · iPhone 17", "U1", "Shutdown", true)], live: [], prunable: ["moved"], recorded: [("U1", "moved")])
        #expect(await WorktreeLeftoversCheck().run(context) == .warn("`xcrew · App · moved · iPhone 17` (its worktree is gone); `xcrun simctl delete U1` removes it"))
    }

    /// One whose runtime the Mac has lost can't run; several are removed by one command.
    @Test func aRuntimeGoneIsNamedThoughItsWorktreeLivesAndSeveralShareOneCommand() async throws {
        let context = try Self.leftovers([("xcrew · App · live", "U2", "Shutdown", false), ("xcrew · App · old", "U1", "Shutdown", true)], live: ["live"], recorded: [("U2", "live"), ("U1", "old")])
        #expect(await WorktreeLeftoversCheck().run(context) == .warn("`xcrew · App · live` (its runtime is gone), `xcrew · App · old` (its worktree is gone); `xcrun simctl delete U2 U1` removes them"))
    }

    /// Only what setup recorded is judged: a simulator named like one of xcrew's, as another clone of a folder of the same
    /// name makes, is never named, nor a recorded one already deleted.
    @Test func whatSetupDidntRecordIsLeftAlone() async throws {
        let context = try Self.leftovers([("xcrew · App · feat", "U3", "Shutdown", true), ("xcrew · App · live", "U2", "Booted", true)], live: ["live"], recorded: [("U2", "live"), ("GONE", "old")])
        #expect(await WorktreeLeftoversCheck().run(context) == .pass("1 made for this repository's worktrees, each still there"))
    }

    /// Setup may have been given the worktree's folder in another letter case than git keeps; both name one folder.
    @Test func aRecordSpelledInAnotherCaseIsTheSameWorktree() async throws {
        let context = try Self.leftovers([("xcrew · App · mytree", "U1", "Shutdown", true)], live: ["MyTree"], recorded: [("U1", "mytree")])
        #expect(await WorktreeLeftoversCheck().run(context) == .pass("1 made for this repository's worktrees, each still there"))
    }

    @Test func withNothingRecordedTheCheckSkips() async throws {
        let context = try Self.leftovers([("xcrew · App · old", "U1", "Shutdown", true)], live: [], recorded: [])
        #expect(await WorktreeLeftoversCheck().run(context).status == .skip)
        #expect(await WorktreeLeftoversCheck().run(.fake(FakeRunner(responses: ["xcrun simctl list devices --json": Self.devices([])]))).status == .skip)
    }

    /// `hw.memsize` for a Mac of `gigabytes` GB.
    static func memory(_ booted: Int, gigabytes: Int?) -> FakeRunner {
        let devices = (0..<booted).map { ("iPhone \($0)", "B\($0)", "Booted", true) } + [("iPad", "S1", "Shutdown", true)]
        var responses: [String: CommandResult] = [
            "pgrep -x com.apple.CoreSimulator.CoreSimulatorService": .init(status: 0, stdout: "1\n"),
            "xcrun simctl list devices booted --json": Self.devices(devices),
        ]
        if let gigabytes { responses["sysctl -n hw.memsize"] = .init(status: 0, stdout: "\(gigabytes << 30)\n") }
        return FakeRunner(responses: responses)
    }

    @Test func belowThreeQuartersOfMemoryByTheLowerMeasureItPasses() async {
        let result = await SimulatorMemoryCheck().run(.fake(Self.memory(3, gigabytes: 32)))
        #expect(result == .pass("3 booted: about 19–33 GB by two measures that disagree (measured on one Mac), of 32 GB"))
    }

    /// Four settled simulators take 26 GB by the lower measure, past three quarters of 32 GB.
    @Test func atThreeQuartersItWarnsOffThePromptNamingTheBootedOnes() async {
        let result = await SimulatorMemoryCheck().run(.fake(Self.memory(4, gigabytes: 32)))
        #expect(result == .warn("4 booted simulators take about 26–44 GB by two measures that disagree (measured on one Mac), of 32 GB; `xcrun simctl shutdown <name>` shuts one down: iPhone 0, iPhone 1, iPhone 2, iPhone 3"))
        #expect(result.isOffThePrompt)
    }

    @Test func noneBootedPassesAndAnUnknownMemorySkips() async {
        #expect(await SimulatorMemoryCheck().run(.fake(Self.memory(0, gigabytes: 32))) == .pass("none booted"))
        #expect(await SimulatorMemoryCheck().run(.fake(Self.memory(2, gigabytes: nil))).status == .skip)
    }

    /// With no CoreSimulator service running, none is booted, and `simctl` isn't asked, since `xcrun` would start it. A
    /// `simctl` that doesn't answer says nothing booted or not.
    @Test func noServiceIsNoneBootedAndASilentSimctlSkips() async {
        var runner = Self.memory(2, gigabytes: 32)
        runner.responses["pgrep -x com.apple.CoreSimulator.CoreSimulatorService"] = .init(status: 1)
        #expect(await SimulatorMemoryCheck().run(.fake(runner)) == .pass("none booted"))
        runner = Self.memory(2, gigabytes: 32)
        runner.responses["xcrun simctl list devices booted --json"] = .timedOut
        #expect(await SimulatorMemoryCheck().run(.fake(runner)).status == .skip)
    }
}

/// What `setup --worktree` keeps of the simulators it made, so the doctor never guesses from a name.
@Suite struct WorktreeSimulatorRecordTests {
    @Test func aRecordReadsBackWhatWasAddedOnceForEachId() throws {
        let folder = Project.temporary(containing: ["trees/feat"]).root
        let file = folder.appending(path: ".git/xcrew/worktree-simulators")
        let record = WorktreeSimulatorRecord().adding("U1", for: folder.appending(path: "trees/old")).adding("U1", for: folder.appending(path: "trees/feat"))
        try record.write(to: file)
        let read = WorktreeSimulatorRecord.read(file)
        #expect(read.entries.map(\.udid) == ["U1"])
        #expect(read.entries.first?.worktree == ProjectLayout.canonical(folder.appending(path: "trees/feat")))
        #expect(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path) == ["worktree-simulators"])
        #expect(WorktreeSimulatorRecord.read(folder.appending(path: "none")).entries.isEmpty)
    }

    @Test func theRecordSitsInTheCommonGitFolder() async {
        let runner = FakeRunner(responses: ["git -C /work/trees/feat rev-parse --path-format=absolute --git-common-dir": .init(status: 0, stdout: "/work/App/.git\n")])
        #expect(await WorktreeSimulatorRecord.file(for: URL(fileURLWithPath: "/work/trees/feat"), using: runner)?.path == "/work/App/.git/xcrew/worktree-simulators")
        #expect(await WorktreeSimulatorRecord.file(for: URL(fileURLWithPath: "/elsewhere"), using: runner) == nil)
    }
}
