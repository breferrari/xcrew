import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// The doctor's storage budget: this project's MobileBuildMCP workspaces against a budget, from `purge --report` for each
/// of its checkouts' workspaces, with the dry run that lists what would go and no deletion.
@Suite struct StorageBudgetTests {
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
    func runner(environment: [String: String] = [:], purgeAnswers: Bool = true) throws -> FakeRunner {
        let all = SpaceTests.purgeReport(key: RunLog.workspaceKey(root: root), renamed: ["field-05686ffe76ea": RunLog.workspaceKey(root: worktree)])
        var responses = SpaceTests.git(root: root, worktrees: [worktree])
        if purgeAnswers {
            for checkout in [root, worktree] {
                let key = RunLog.workspaceKey(root: checkout)
                responses["mobilebuildmcp purge --report --scope workspace --workspace-key \(key) --json"] = .init(status: 0, stdout: try Self.scoped(all, key: key))
            }
        }
        return FakeRunner(installed: ["mobilebuildmcp"], responses: responses)
    }

    func context(environment: [String: String] = [:], purgeAnswers: Bool = true) throws -> CheckContext {
        CheckContext(project: project, machine: Machine(environment: environment, home: home, runner: try runner(purgeAnswers: purgeAnswers)))
    }

    /// Sizing every workspace on a Mac took 21.7 s where this project's alone took 0.8 s (a field report, about 190 GB):
    /// the check asks for each of this project's checkouts' workspaces, once each, and never for the whole Mac. A checkout
    /// is keyed by its path as written and as the file system spells it, since MobileBuildMCP keys by the path it's given:
    /// the temporary root is `/var/…` as written, `/private/var/…` spelled.
    @Test func itReadsOnlyThisProjectsWorkspacesOnceEach() async throws {
        let recording = RecordingRunner(try runner())
        _ = await StorageBudgetCheck().run(CheckContext(project: project, machine: Machine(environment: [:], home: home, runner: recording)))
        let reports = recording.asked.filter { $0.hasPrefix("mobilebuildmcp purge --report") }
        let keys = Set([root, ProjectLayout.canonicalPath(root), worktree].map(RunLog.workspaceKey(root:)))
        #expect(reports.sorted() == keys.map { "mobilebuildmcp purge --report --scope workspace --workspace-key \($0) --json" }.sorted())
        #expect(!reports.contains { $0.contains("--scope all") })
    }

    /// The main checkout's and the worktree's together.
    @Test func withinTheBudgetItPassesWithTheTotalAndTheBudget() async throws {
        let result = await StorageBudgetCheck().run(try context())
        #expect(result == .pass("this project's MobileBuildMCP workspaces take 84.8 MB, within its budget of 40 GB (XCREW_STORAGE_BUDGET_GB sets another)"))
    }

    @Test func pastTheBudgetItNamesTheLargestWorkspaceAndTheDryRun() async throws {
        let result = await StorageBudgetCheck().run(CheckContext(project: project, machine: Machine(environment: ["XCREW_STORAGE_BUDGET_GB": "0.05"], home: home, runner: try runner())))
        let key = RunLog.workspaceKey(root: root)
        #expect(result == .warn("this project's MobileBuildMCP workspaces take 84.8 MB, past its budget of 0.05 GB (XCREW_STORAGE_BUDGET_GB sets another); the largest, App (\(root)), takes 81.5 MB: `mobilebuildmcp purge --dry-run --scope workspace --workspace-key \(key) --classes \(Self.classes)` lists what it would delete"))
    }

    /// A budget it can't use, not a finite positive number of GB it can say, is the default.
    @Test(arguments: ["lots", "0", "-5", "inf", "nan", "1e20"])
    func aBudgetItCantUseIsTheDefault(_ value: String) async throws {
        #expect(await StorageBudgetCheck().run(CheckContext(project: project, machine: Machine(environment: ["XCREW_STORAGE_BUDGET_GB": value], home: home, runner: try runner()))).message.hasSuffix("within its budget of 40 GB (XCREW_STORAGE_BUDGET_GB sets another)"))
    }

    @Test func withoutAReportItSkips() async throws {
        #expect(await StorageBudgetCheck().run(try context(purgeAnswers: false)).status == .skip)
    }

    /// It walks every file, so the line above the prompt never waits on it.
    @Test func itStaysOffThePromptsDoctor() {
        #expect(!StorageBudgetCheck().isOnPrompt)
        #expect(Doctor.checks.contains { $0.id == "mobilebuildmcp/storage" })
    }
}
