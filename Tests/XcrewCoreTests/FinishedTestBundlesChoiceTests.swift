import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// Whether the person chose to drop finished test bundles, kept once for every checkout of the repository.
@Suite struct FinishedTestBundlesChoiceTests {
    let project = Project.temporary()
    var common: URL { project.root.appending(path: ".git") }
    var runner: FakeRunner {
        FakeRunner(responses: ["git -C \(project.root.path) rev-parse --path-format=absolute --git-common-dir": .init(status: 0, stdout: "\(common.path)\n")])
    }

    @Test func itKeepsUntilThePersonChoosesToDrop() async throws {
        #expect(await FinishedTestBundlesChoice.read(for: project, using: runner) == .keep)

        try await FinishedTestBundlesChoice.drop.write(for: project, using: runner)

        #expect(await FinishedTestBundlesChoice.read(for: project, using: runner) == .drop)
        #expect(try String(contentsOf: common.appending(path: "xcrew/finished-test-bundles"), encoding: .utf8) == "drop\n")
    }

    @Test func keepingAgainUndoesIt() async throws {
        try await FinishedTestBundlesChoice.drop.write(for: project, using: runner)
        try await FinishedTestBundlesChoice.keep.write(for: project, using: runner)

        #expect(await FinishedTestBundlesChoice.read(for: project, using: runner) == .keep)
    }

    @Test func outsideGitThereIsNoneAndItCantBeChanged() async {
        let outside = FakeRunner()

        #expect(await FinishedTestBundlesChoice.read(for: project, using: outside) == nil)
        await #expect(throws: FinishedTestBundlesChoice.NotInGit.self) { try await FinishedTestBundlesChoice.drop.write(for: project, using: outside) }
    }
}
