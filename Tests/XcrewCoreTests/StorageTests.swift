import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// MobileBuildMCP's storage as `mobilebuildmcp purge --report --json` reports it, read from a capture of its answer
/// (docs/findings.md, *Disk space*).
@Suite struct StorageReportTests {
    static let all = try! Data(contentsOf: Bundle.module.url(forResource: "purgeReportAll", withExtension: "json", subdirectory: "Fixtures/Storage")!)

    @Test func eachWorkspaceIsReadWithItsClasses() throws {
        let report = try #require(StorageReport(json: Self.all))
        #expect(report.bytes == 85_082_639)
        #expect(report.workspaces.map(\.key) == ["kit-0a1b2c3d4e5f", "field-05686ffe76ea", "field-09f4495eb86d", "app-7f5863af5761"])
        let kit = try #require(report.workspaces.first)
        #expect(kit.bytes == 81_520_997)
        let derivedData = try #require(kit.classes["derivedData"])
        #expect(derivedData.bytes == 77_912_189 && derivedData.exists)
        #expect(abs((derivedData.newest?.timeIntervalSince1970 ?? 0) - 1_793_344_120.084711) < 0.001)
        #expect(report.workspaces.last?.classes["derivedData"]?.exists == false)
        #expect(report.workspaces[2].classes["logs"]?.bytes == 305_534)
    }

    /// An answer that isn't the report, as from a version that words it otherwise, is none.
    @Test func anotherAnswerIsNoReport() {
        #expect(StorageReport(json: Data(#"{"action":"report"}"#.utf8)) == nil)
        #expect(StorageReport(json: Data("not json".utf8)) == nil)
    }

    /// One workspace's report, asked by its key, without a deletion mode that would need confirming.
    @Test func oneWorkspaceIsAskedByItsKey() async {
        let runner = FakeRunner(responses: ["mobilebuildmcp purge --report --scope workspace --workspace-key kit-0a1b2c3d4e5f --json": .init(status: 0, stdout: String(decoding: Self.all, as: UTF8.self))])
        #expect(await StorageReport.read(.workspace("kit-0a1b2c3d4e5f"), using: runner)?.bytes == 85_082_639)
        #expect(await StorageReport.read(.all, using: runner) == nil)
    }
}

/// The MobileBuildMCP workspaces of a project's checkouts, and the root of a workspace its build log names.
@Suite struct ProjectWorkspacesTests {
    /// The main checkout and a Claude Code worktree, each its own workspace, a family apart by MobileBuildMCP's count.
    @Test func eachLiveCheckoutHasItsKey() async {
        let runner = FakeRunner(responses: [
            "git -C /work/App rev-parse --show-prefix": .init(status: 0, stdout: "\n"),
            "git -C /work/App worktree list --porcelain": .init(status: 0, stdout: "worktree /work/App\nHEAD 0123\nbranch refs/heads/main\n\nworktree /work/App/.claude/worktrees/fix\nHEAD 4567\nbranch refs/heads/worktree-fix\n"),
        ])
        let live = await ProjectWorkspaces.live(of: Project(root: URL(fileURLWithPath: "/work/App")), using: runner)
        #expect(live == [.init(root: "/work/App", key: "App-fc001cdb6ae6", top: "/work/App"), .init(root: "/work/App/.claude/worktrees/fix", key: "fix-a7a71a1a86d1", top: "/work/App/.claude/worktrees/fix")])
    }

    /// A worktree git still lists but whose folder is gone, `prunable`, isn't a live checkout.
    @Test func aPrunableWorktreeIsntLive() async {
        let runner = FakeRunner(responses: [
            "git -C /work/App rev-parse --show-prefix": .init(status: 0, stdout: "\n"),
            "git -C /work/App worktree list --porcelain": .init(status: 0, stdout: "worktree /work/App\nHEAD 0123\nbranch refs/heads/main\n\nworktree /work/App/.claude/worktrees/fix\nHEAD 4567\nbranch refs/heads/worktree-fix\nprunable gitdir file points to non-existent location\n"),
        ])
        #expect(await ProjectWorkspaces.live(of: Project(root: URL(fileURLWithPath: "/work/App")), using: runner) == [.init(root: "/work/App", key: "App-fc001cdb6ae6", top: "/work/App")])
    }

    /// Outside git, the project alone.
    @Test func outsideGitTheProjectAlone() async {
        let live = await ProjectWorkspaces.live(of: Project(root: URL(fileURLWithPath: "/work/App")), using: FakeRunner())
        #expect(live == [.init(root: "/work/App", key: "App-fc001cdb6ae6", top: "/work/App")])
    }

    func workspace(_ key: String, log: String?) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "xcrew-tests-\(UUID().uuidString)/\(key)")
        try FileManager.default.createDirectory(at: folder.appending(path: "logs"), withIntermediateDirectories: true)
        if let log { try log.write(to: folder.appending(path: "logs/build_sim_2026-10-30T10-00-00-000Z_pid1_ab.log"), atomically: true, encoding: .utf8) }
        return folder
    }

    /// The workspace's build log names the container its root holds, a folder down or at the root; the key's hash says
    /// which folder is the root.
    @Test(arguments: ["/work/App/App.xcworkspace", "/work/App/ios/App.xcodeproj"])
    func aRootIsRecoveredFromTheBuildLogAndConfirmedByTheKey(_ container: String) throws {
        let flag = container.hasSuffix(".xcworkspace") ? "-workspace" : "-project"
        let folder = try workspace("App-fc001cdb6ae6", log: "xcodebuild build \(flag) \(container) -scheme App\n")
        #expect(ProjectWorkspaces.root(ofWorkspace: folder) == "/work/App")
    }

    /// A container whose folders don't hash to the key isn't the workspace's root, nor is a log naming none.
    @Test func aRootTheKeyDoesntConfirmIsNone() throws {
        #expect(ProjectWorkspaces.root(ofWorkspace: try workspace("App-fc001cdb6ae6", log: "xcodebuild build -workspace /work/Other/Other.xcworkspace\n")) == nil)
        #expect(ProjectWorkspaces.root(ofWorkspace: try workspace("App-fc001cdb6ae6", log: "nothing here\n")) == nil)
        #expect(ProjectWorkspaces.root(ofWorkspace: try workspace("App-fc001cdb6ae6", log: nil)) == nil)
    }
}
