import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// The other worktrees' runs the band shows, read from MobileBuildMCP's logs in their workspaces.
@Suite struct OtherRunsTests {
    /// In the temporary folder as the file system spells it, `/private` included, as `git worktree list` gives it.
    let base = URL(fileURLWithPath: ProjectLayout.canonicalPath(FileManager.default.temporaryDirectory.path)).appending(path: "xcrew-tests-\(UUID().uuidString)")
    var home: URL { base.appending(path: "home") }
    var main: URL { base.appending(path: "App") }
    func worktree(_ name: String) -> URL { base.appending(path: "trees/\(name)") }
    static let now = Date(timeIntervalSince1970: 1_793_577_600)

    /// A log in `root`'s workspace, written `ago` seconds before now.
    func log(_ name: String, in root: URL, ago: TimeInterval, text: String) throws {
        let folder = home.appending(path: "Library/Developer/MobileBuildMCP/workspaces/\(RunLog.workspaceKey(root: root.path))/logs")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Self.now.addingTimeInterval(-ago)], ofItemAtPath: url.path)
    }

    /// This checkout is `main`; `worktrees` are its linked ones, made on disk unless named in `missing`.
    func going(worktrees: [String], missing: Set<String> = []) async throws -> [OtherRuns.Run] {
        try FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
        for name in worktrees where !missing.contains(name) { try FileManager.default.createDirectory(at: worktree(name), withIntermediateDirectories: true) }
        // `Project` standardizes the path, dropping `/private`: git is asked under that spelling.
        let project = Project(root: main)
        let responses: [String: CommandResult] = [
            "git -C \(project.root.path) rev-parse --show-prefix": .init(status: 0, stdout: "\n"),
            "git -C \(project.root.path) worktree list --porcelain": FakeRunner.worktreeList(main: main.path, linked: worktrees.map { worktree($0).path }),
        ]
        let machine = Machine(environment: [:], home: home, runner: FakeRunner(responses: responses))
        return await OtherRuns.going(project: project, machine: machine, now: Self.now)
    }

    static let testing = "Testing started\nTest Case '-[AppTests.GreetingTests testHello]' started.\n"

    @Test func anotherWorktreesRunIsListedWithItsToolAndPhase() async throws {
        try log("test_sim_2026-11-01T23-59-00-000Z_pid100_a.log", in: worktree("feature"), ago: 5, text: Self.testing)
        let runs = try await going(worktrees: ["feature"])
        #expect(runs.map(\.worktree) == ["feature"])
        #expect(runs.first?.tool == "test_sim")
        #expect(runs.first?.root == worktree("feature").path)
        #expect(runs.first?.phase != nil)
    }

    /// A run that printed its verdict has ended; one quiet longer than `quietFor` was stopped, or ended unread.
    @Test func anEndedOrLongQuietRunIsNotListed() async throws {
        try log("build_sim_2026-11-01T23-59-00-000Z_pid100_a.log", in: worktree("done"), ago: 5, text: "Build started\n** BUILD SUCCEEDED **\n")
        try log("test_sim_2026-11-01T23-50-00-000Z_pid100_a.log", in: worktree("quiet"), ago: 91, text: Self.testing)
        try log("test_sim_2026-11-01T23-59-00-000Z_pid100_a.log", in: worktree("busy"), ago: 89, text: Self.testing)
        #expect(try await going(worktrees: ["done", "quiet", "busy"]).map(\.worktree) == ["busy"])
    }

    /// This session's own runs are on its band already; other logs MobileBuildMCP keeps aren't runs.
    @Test func thisCheckoutsRunsAndOtherLogsAreLeftOut() async throws {
        try log("test_sim_2026-11-01T23-59-00-000Z_pid100_a.log", in: main, ago: 5, text: Self.testing)
        try log("build_sim_parser-debug_2026-11-01T23-59-00-000Z_pid100_a.log", in: worktree("feature"), ago: 5, text: "debug\n")
        try log("app_oslog_2026-11-01T23-59-00-000Z_pid100_a.log", in: worktree("feature"), ago: 5, text: "log\n")
        #expect(try await going(worktrees: ["feature"]).isEmpty)
    }

    /// A worktree whose folder is gone, or a workspace that can't be read, is skipped, never shown as a run.
    @Test func aGoneWorktreeOrAnUnreadableWorkspaceIsSkipped() async throws {
        try log("test_sim_2026-11-01T23-59-00-000Z_pid100_a.log", in: worktree("gone"), ago: 5, text: Self.testing)
        try log("test_sim_2026-11-01T23-59-00-000Z_pid100_a.log", in: worktree("locked"), ago: 5, text: Self.testing)
        let logs = home.appending(path: "Library/Developer/MobileBuildMCP/workspaces/\(RunLog.workspaceKey(root: worktree("locked").path))/logs")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: logs.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: logs.path) }
        #expect(try await going(worktrees: ["gone", "locked"], missing: ["gone"]).isEmpty)
    }

    @Test func outsideGitNoneIsListed() async {
        let machine = Machine(environment: [:], home: home, runner: FakeRunner())
        #expect(await OtherRuns.going(project: Project(root: main), machine: machine, now: Self.now).isEmpty)
    }
}
