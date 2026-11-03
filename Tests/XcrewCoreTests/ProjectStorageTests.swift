import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// This project's MobileBuildMCP storage: its checkouts' workspaces together, from `purge --report`, sized and nothing
/// more.
@Suite struct ProjectStorageTests {
    /// In the temporary folder as the file system spells it, `/private` included, as a listing gives its paths back.
    let home = URL(fileURLWithPath: ProjectLayout.canonicalPath(FileManager.default.temporaryDirectory.path)).appending(path: "xcrew-tests-\(UUID().uuidString)")
    /// This project, in a folder named `App`, its workspace the capture's largest (81.5 MB).
    let project: Project
    var root: String { project.root.path }
    /// A linked worktree of it, whose workspace is the capture's second (3.3 MB).
    var worktree: String { home.appending(path: "trees/feature").path }

    init() {
        let folder = FileManager.default.temporaryDirectory.appending(path: "xcrew-tests-\(UUID().uuidString)/App")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        project = Project(root: folder)
    }

    static let classes = "derivedData,logs,resultBundles,stateTransients,testProducts"
    static let goneClasses = "logs,resultBundles,stateTransients,testProducts"

    /// The captured Mac's report, `purge --report --scope workspace` for one workspace: the capture's `--scope all` report
    /// with that workspace alone in it, as MobileBuildMCP scopes one.
    static func scoped(_ all: String, key: String) throws -> String {
        var report = try #require(try JSONSerialization.jsonObject(with: Data(all.utf8)) as? [String: Any])
        let workspaces = (report["workspaces"] as? [[String: Any]] ?? []).filter { $0["workspaceKey"] as? String == key }
        report["workspaces"] = workspaces
        report["totals"] = ["bytes": workspaces.compactMap { ($0["totals"] as? [String: Any])?["bytes"] as? Int }.reduce(0, +)]
        return String(decoding: try JSONSerialization.data(withJSONObject: report), as: UTF8.self)
    }

    /// The captured Mac: this project's workspace and its worktree's, each answering its own workspace's report.
    func runner(environment: [String: String] = [:], purgeAnswers: Bool = true, ps: String? = nil) throws -> FakeRunner {
        let all = SpaceTests.purgeReport(key: RunLog.workspaceKey(root: root), renamed: ["field-05686ffe76ea": RunLog.workspaceKey(root: worktree)])
        var responses = SpaceTests.git(root: root, worktrees: [worktree])
        if purgeAnswers {
            for checkout in [root, worktree] {
                let key = RunLog.workspaceKey(root: checkout)
                responses["mobilebuildmcp purge --report --scope workspace --workspace-key \(key) --json"] = .init(status: 0, stdout: try Self.scoped(all, key: key))
            }
        }
        if let ps { responses["ps -axo pid=,ppid=,etime=,command="] = .init(status: 0, stdout: ps) }
        return FakeRunner(installed: ["mobilebuildmcp"], responses: responses)
    }

    func context(environment: [String: String] = [:], purgeAnswers: Bool = true) throws -> CheckContext {
        CheckContext(project: project, machine: Machine(environment: environment, home: home, runner: try runner(purgeAnswers: purgeAnswers)))
    }

    /// The captured Mac's workspaces of this project, its main checkout's and its worktree's, as `xcrew space` reads them.
    func live() throws -> [(workspace: StorageReport.Workspace, checkout: ProjectWorkspaces.Checkout)] {
        let all = SpaceTests.purgeReport(key: RunLog.workspaceKey(root: root), renamed: ["field-05686ffe76ea": RunLog.workspaceKey(root: worktree)])
        let report = try #require(StorageReport(json: Data(all.utf8)))
        return [root, worktree].compactMap { checkout in
            let key = RunLog.workspaceKey(root: checkout)
            return report.workspaces.first { $0.key == key }.map { (workspace: $0, checkout: ProjectWorkspaces.Checkout(root: checkout, key: key)) }
        }
    }

    func line(environment: [String: String] = [:], ps: String = "") throws -> String {
        ProjectStorage.line(try live(), machine: Machine(environment: environment, home: home, runner: FakeRunner()), processes: ProcessList(ps: ps))
    }

    /// The main checkout's and the worktree's together, in both units, and the class that takes the most: what takes the
    /// space, with nothing to measure it against.
    @Test func itSaysTheTotalAndTheClassThatTakesTheMost() async throws {
        #expect(try line() == "this project's MobileBuildMCP workspaces take 84.8 MB (80.8 MiB as `du -h` counts); DerivedData takes the most, 77.9 MB")
    }

    /// Read while a build writes to one of its workspaces, the figure is that build's too, and says so.
    @Test func aFigureTakenWhileABuildWritesSaysSo() async throws {
        let derived = home.appending(path: "Library/Developer/MobileBuildMCP/workspaces/\(RunLog.workspaceKey(root: root))/DerivedData").path
        let ps = "  10 1 05:00 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -scheme App -derivedDataPath \(derived) -destination id=1\n"
        #expect(try line(ps: ps) == "this project's MobileBuildMCP workspaces take 84.8 MB (80.8 MiB as `du -h` counts); DerivedData takes the most, 77.9 MB; a build is writing to them now, so they take more than they will after it")
    }

    /// No variable sets a budget: the line is the same whatever the environment holds.
    @Test func noVariableChangesTheLine() async throws {
        #expect(try line(environment: ["XCREW_STORAGE_BUDGET_GB": "0.05"]) == line())
    }
}
