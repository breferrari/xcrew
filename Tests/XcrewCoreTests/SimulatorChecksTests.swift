import Foundation
import Testing
import XcrewTestSupport

@testable import XcrewCore

/// The doctor's simulator upkeep: what `setup --worktree` left behind.
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
        let result = await WorktreeLeftovers.run(context)
        #expect(result == .warn("`xcrew · App · old` (its worktree is gone). Deleting it loses the apps installed on it and their data, so it's the person's to agree to: `xcrun simctl delete U1`"))
        #expect(result.isOffThePrompt == false)
    }

    /// git calls a worktree whose folder was deleted prunable: it's gone too.
    @Test func aPrunableWorktreeCountsAsGone() async throws {
        let context = try Self.leftovers([("xcrew · App · moved · iPhone 17", "U1", "Shutdown", true)], live: [], prunable: ["moved"], recorded: [("U1", "moved")])
        #expect(await WorktreeLeftovers.run(context) == .warn("`xcrew · App · moved · iPhone 17` (its worktree is gone). Deleting it loses the apps installed on it and their data, so it's the person's to agree to: `xcrun simctl delete U1`"))
    }

    /// One whose runtime the Mac has lost can't run; several are removed by one command.
    @Test func aRuntimeGoneIsNamedThoughItsWorktreeLivesAndSeveralShareOneCommand() async throws {
        let context = try Self.leftovers([("xcrew · App · live", "U2", "Shutdown", false), ("xcrew · App · old", "U1", "Shutdown", true)], live: ["live"], recorded: [("U2", "live"), ("U1", "old")])
        #expect(await WorktreeLeftovers.run(context) == .warn("`xcrew · App · live` (its runtime is gone), `xcrew · App · old` (its worktree is gone). Deleting them loses the apps installed on them and their data, so it's the person's to agree to: `xcrun simctl delete U2 U1`"))
    }

    /// Only what setup recorded is judged: a simulator named like one of xcrew's, as another clone of a folder of the same
    /// name makes, is never named, nor a recorded one already deleted.
    @Test func whatSetupDidntRecordIsLeftAlone() async throws {
        let context = try Self.leftovers([("xcrew · App · feat", "U3", "Shutdown", true), ("xcrew · App · live", "U2", "Booted", true)], live: ["live"], recorded: [("U2", "live"), ("GONE", "old")])
        #expect(await WorktreeLeftovers.run(context) == .pass("1 made for this repository's worktrees, each still there"))
    }

    /// Every simulator setup recorded is deleted since: none is left, said plainly rather than as a count of 0.
    @Test func noneLeftOfThoseMadeIsSaidPlainly() async throws {
        let context = try Self.leftovers([("iPhone 18 Pro", "OTHER", "Shutdown", true)], live: ["live"], recorded: [("GONE", "live")])
        #expect(await WorktreeLeftovers.run(context) == .pass("none of those made for this repository's worktrees is left"))
    }

    /// Setup may have been given the worktree's folder in another letter case than git keeps; both name one folder.
    @Test func aRecordSpelledInAnotherCaseIsTheSameWorktree() async throws {
        let context = try Self.leftovers([("xcrew · App · mytree", "U1", "Shutdown", true)], live: ["MyTree"], recorded: [("U1", "mytree")])
        #expect(await WorktreeLeftovers.run(context) == .pass("1 made for this repository's worktrees, each still there"))
    }

    /// `xcrew space` says it, in a part of its own, as it says what else takes room; the doctor doesn't.
    @Test func xcrewSpaceNamesALeftoverSimulator() async throws {
        let context = try Self.leftovers([("xcrew · App · old", "U1", "Shutdown", true)], live: [], recorded: [("U1", "old")])
        #expect(await Space.worktreePart(context) == SpaceReport.Part(title: "Simulators setup made for worktrees", lines: [SpaceReport.Line(text: "`xcrew · App · old` (its worktree is gone). Deleting it loses the apps installed on it and their data, so it's the person's to agree to: `xcrun simctl delete U1`")]))
    }

    @Test func withNothingRecordedTheCheckSkips() async throws {
        let context = try Self.leftovers([("xcrew · App · old", "U1", "Shutdown", true)], live: [], recorded: [])
        #expect(await WorktreeLeftovers.run(context).status == .skip)
        #expect(await WorktreeLeftovers.run(.fake(FakeRunner(responses: ["xcrun simctl list devices --json": Self.devices([])]))).status == .skip)
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
