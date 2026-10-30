import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// The doctor's storage budget: this project's MobileBuildMCP workspaces against a budget, and the Mac's workspaces whose
/// project folder is gone, from the captured `purge --report`, with the dry run that lists what would go and no deletion.
@Suite struct StorageBudgetTests {
    let home = URL(fileURLWithPath: ProjectLayout.canonicalPath(FileManager.default.temporaryDirectory.path)).appending(path: "xcrew-tests-\(UUID().uuidString)")
    /// This project, in a folder named `App`, its workspace the capture's largest (81.5 MB).
    let project: Project
    var root: String { project.root.path }
    var key: String { RunLog.workspaceKey(root: root) }

    init() {
        let folder = FileManager.default.temporaryDirectory.appending(path: "xcrew-tests-\(UUID().uuidString)/App")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        project = Project(root: folder)
    }

    static let classes = "derivedData,logs,resultBundles,stateTransients,testProducts"
    static let goneClasses = "logs,resultBundles,stateTransients,testProducts"

    /// The captured Mac, with this project's workspace under its key; a workspace whose log names a project gone from
    /// `/work/Gone` when `gone`; and `environment` for the budget.
    func context(gone: Bool, environment: [String: String] = [:], purgeAnswers: Bool = true) throws -> CheckContext {
        let purge = SpaceTests.fixture("purgeReportAll").replacingOccurrences(of: "kit-0a1b2c3d4e5f", with: key).replacingOccurrences(of: "field-09f4495eb86d", with: "Gone-86d710d9ba22")
        if gone {
            let log = home.appending(path: "Library/Developer/MobileBuildMCP/workspaces/Gone-86d710d9ba22/logs/build_sim_1.log")
            try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "xcodebuild build -workspace /work/Gone/Gone.xcworkspace -scheme Gone\n".write(to: log, atomically: true, encoding: .utf8)
        }
        var responses: [String: CommandResult] = [
            "git -C \(root) rev-parse --show-prefix": .init(status: 0, stdout: "\n"),
            "git -C \(root) worktree list --porcelain": .init(status: 0, stdout: "worktree \(root)\nHEAD 0123\nbranch refs/heads/main\n"),
        ]
        if purgeAnswers { responses["mobilebuildmcp purge --report --scope all --json"] = .init(status: 0, stdout: purge) }
        return CheckContext(project: project, machine: Machine(environment: environment, home: home, runner: FakeRunner(installed: ["mobilebuildmcp"], responses: responses)))
    }

    @Test func withinTheBudgetItPassesWithTheTotalAndTheBudget() async throws {
        let result = await StorageBudgetCheck().run(try context(gone: false))
        #expect(result == .pass("this project's MobileBuildMCP workspaces take 81.5 MB, within its budget of 40 GB (XCREW_STORAGE_BUDGET_GB sets another)"))
    }

    @Test func pastTheBudgetItNamesTheLargestWorkspaceAndTheDryRun() async throws {
        let result = await StorageBudgetCheck().run(try context(gone: false, environment: ["XCREW_STORAGE_BUDGET_GB": "0.05"]))
        #expect(result == .warn("this project's MobileBuildMCP workspaces take 81.5 MB, past its budget of 0.05 GB (XCREW_STORAGE_BUDGET_GB sets another); the largest, App (\(root)), takes 81.5 MB: `mobilebuildmcp purge --dry-run --scope workspace --workspace-key \(key) --classes \(Self.classes)` lists what it would free"))
    }

    /// A confirmed-gone root is no one's: named whatever the budget, as the Mac's, each by its own key.
    @Test func workspacesWhoseProjectFolderIsGoneAreNamedAsTheMacs() async throws {
        let result = await StorageBudgetCheck().run(try context(gone: true))
        #expect(result == .warn("on this Mac, 1 workspace whose project folder is gone takes 305.5 KB: `mobilebuildmcp purge --dry-run --scope workspace --workspace-key Gone-86d710d9ba22 --classes \(Self.goneClasses)` lists it"))
        #expect(!result.message.contains("--scope all"))
    }

    @Test func aBudgetThatIsntANumberIsTheDefault() async throws {
        #expect(await StorageBudgetCheck().run(try context(gone: false, environment: ["XCREW_STORAGE_BUDGET_GB": "lots"])).status == .pass)
    }

    @Test func withoutAReportItSkips() async throws {
        #expect(await StorageBudgetCheck().run(try context(gone: false, purgeAnswers: false)).status == .skip)
    }

    /// It walks every file, so the line above the prompt never waits on it.
    @Test func itStaysOffThePromptsDoctor() {
        #expect(!StorageBudgetCheck().isOnPrompt)
        #expect(Doctor.checks.filter { !$0.isOnPrompt }.map(\.id).contains("mobilebuildmcp/storage"))
    }
}
