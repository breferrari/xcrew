import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// The doctor's storage budget: this project's MobileBuildMCP workspaces against a budget, and the Mac's workspaces whose
/// project folder is gone, from the captured `purge --report`, with the dry run that lists what would go and no deletion.
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

    /// The captured Mac: this project's workspace and its worktree's; and for each of `gone`, a capture's workspace whose
    /// log names a project folder of that name gone from this test's home.
    func context(gone: [(fixture: String, name: String)] = [], environment: [String: String] = [:], purgeAnswers: Bool = true) throws -> CheckContext {
        var renamed = ["field-05686ffe76ea": RunLog.workspaceKey(root: worktree)]
        for entry in gone {
            let goneRoot = home.appending(path: entry.name).path
            renamed[entry.fixture] = RunLog.workspaceKey(root: goneRoot)
            try SpaceTests.writeLog(home: home, key: RunLog.workspaceKey(root: goneRoot), root: goneRoot)
        }
        var responses = SpaceTests.git(root: root, worktrees: [worktree])
        if purgeAnswers {
            responses["mobilebuildmcp purge --report --scope all --json"] = .init(status: 0, stdout: SpaceTests.purgeReport(key: RunLog.workspaceKey(root: root), renamed: renamed))
        }
        return CheckContext(project: project, machine: Machine(environment: environment, home: home, runner: FakeRunner(installed: ["mobilebuildmcp"], responses: responses)))
    }

    /// The main checkout's and the worktree's together.
    @Test func withinTheBudgetItPassesWithTheTotalAndTheBudget() async throws {
        let result = await StorageBudgetCheck().run(try context())
        #expect(result == .pass("this project's MobileBuildMCP workspaces take 84.8 MB, within its budget of 40 GB (XCREW_STORAGE_BUDGET_GB sets another)"))
    }

    @Test func pastTheBudgetItNamesTheLargestWorkspaceAndTheDryRun() async throws {
        let result = await StorageBudgetCheck().run(try context(environment: ["XCREW_STORAGE_BUDGET_GB": "0.05"]))
        let key = RunLog.workspaceKey(root: root)
        #expect(result == .warn("this project's MobileBuildMCP workspaces take 84.8 MB, past its budget of 0.05 GB (XCREW_STORAGE_BUDGET_GB sets another); the largest, App (\(root)), takes 81.5 MB: `mobilebuildmcp purge --dry-run --scope workspace --workspace-key \(key) --classes \(Self.classes)` lists what it would delete"))
    }

    /// A confirmed-gone root is no one's: named whatever the budget, as the Mac's, largest first, each by its own key.
    @Test func workspacesWhoseProjectFolderIsGoneAreNamedAsTheMacs() async throws {
        let result = await StorageBudgetCheck().run(try context(gone: [("field-09f4495eb86d", "Gone"), ("app-7f5863af5761", "Old")]))
        let (gone, old) = (home.appending(path: "Gone").path, home.appending(path: "Old").path)
        let (goneKey, oldKey) = (RunLog.workspaceKey(root: gone), RunLog.workspaceKey(root: old))
        #expect(result == .warn("on this Mac, 2 workspaces whose project folder is gone take 305.6 KB (\(gone), \(old)): `mobilebuildmcp purge --dry-run --scope workspace --workspace-key \(goneKey) --classes \(Self.goneClasses)`, `mobilebuildmcp purge --dry-run --scope workspace --workspace-key \(oldKey) --classes \(Self.goneClasses)` list what they would delete"))
        #expect(!result.message.contains("--scope all"))
    }

    /// A budget it can't use, not a finite positive number of GB it can say, is the default.
    @Test(arguments: ["lots", "0", "-5", "inf", "nan", "1e20"])
    func aBudgetItCantUseIsTheDefault(_ value: String) async throws {
        #expect(await StorageBudgetCheck().run(try context(environment: ["XCREW_STORAGE_BUDGET_GB": value])).message.hasSuffix("within its budget of 40 GB (XCREW_STORAGE_BUDGET_GB sets another)"))
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
