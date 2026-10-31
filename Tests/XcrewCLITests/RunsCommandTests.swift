import Foundation
import Testing
@testable import XcrewCLI
@testable import XcrewCore
import XcrewTestSupport

/// `xcrew runs`: the other worktrees' runs, as the mod reads them for the band.
@Suite struct RunsCommandTests {
    @Test func anotherWorktreesRunIsAnsweredAsJSON() async throws {
        let main = Project.temporary()
        let feature = main.root.deletingLastPathComponent().appending(path: "\(main.root.lastPathComponent)-trees/feature").path
        try FileManager.default.createDirectory(atPath: feature, withIntermediateDirectories: true)
        let logs = main.root.appending(path: "home/Library/Developer/MobileBuildMCP/workspaces/\(RunLog.workspaceKey(root: feature))/logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try "Testing started\n".write(to: logs.appending(path: "test_sim_2026-11-01T23-59-00-000Z_pid100_a.log"), atomically: true, encoding: .utf8)
        let runner = FakeRunner(responses: FakeRunner.worktreeResponses(project: main, main: main.root.path, linked: [feature]))
        let text = await Run("runs", context: .fake(runner, project: main)).text
        let runs = try JSONDecoder().decode([OtherRuns.Run].self, from: Data(text.utf8))
        #expect(runs.map(\.worktree) == ["feature"])
        #expect(runs.map(\.tool) == ["test_sim"])
    }
}
