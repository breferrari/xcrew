import Foundation
import Testing
@testable import XcrewCLI
@testable import XcrewCore
import XcrewTestSupport

/// `xcrew setup --finished-test-bundles` records whether xcrew drops MobileBuildMCP's finished test-run bundles, and
/// `xcrew tidy`, which the mod runs after each test run, drops them only once the person chose to.
@Suite struct FinishedTestBundlesCommandTests {
    let project = Project.temporary(containing: ["App.xcworkspace"])
    var runner: FakeRunner {
        FakeRunner(responses: [
            "xcrun simctl list devices available --json": .init(status: 0, stdout: #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone 18","udid":"U18","isAvailable":true}]}}"#),
            "git -C \(project.root.path) rev-parse --path-format=absolute --git-common-dir": .init(status: 0, stdout: "\(project.root.path)/.git\n"),
            "ps -axo pid=,ppid=,etime=,command=": .init(status: 0, stdout: "    1     0 10:00 /sbin/launchd\n"),
        ])
    }
    var context: CheckContext { .fake(runner, project: project) }

    /// A finished `test_sim` bundle of `time` in this checkout's workspace, with the marker MobileBuildMCP writes once its
    /// run is done, dated `finishedAt`.
    @discardableResult
    func finishedBundle(at time: String = "2026-11-18T09-00-00-000Z", finishedAt: Date = Date(timeIntervalSince1970: 1_794_994_000)) throws -> URL {
        let folder = context.machine.home.appending(path: "Library/Developer/MobileBuildMCP/workspaces/\(RunLog.workspaceKey(root: project.root.path))/test-products")
        let bundle = folder.appending(path: "test_sim_\(time)_pid4242_0a1b2c3d.xctestproducts")
        let marker = folder.appending(path: bundle.lastPathComponent + ".mobilebuildmcp-completed")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data().write(to: marker)
        try FileManager.default.setAttributes([.modificationDate: finishedAt], ofItemAtPath: marker.path)
        return bundle
    }

    @Test func tidyKeepsEveryBundleUntilThePersonChoosesToDrop() async throws {
        let bundle = try finishedBundle()
        try finishedBundle(at: "2026-11-18T10-00-00-000Z", finishedAt: Date(timeIntervalSince1970: 1_794_996_000))

        let run = await Run("tidy", context: context)

        #expect(run.status == 0)
        #expect(run.text == #"{"dropped":0}"#)
        #expect(FileManager.default.fileExists(atPath: bundle.path))
    }

    @Test func setupRecordsDropAndTidyThenDropsFinishedBundlesButTheNewest() async throws {
        let bundle = try finishedBundle()
        let newest = try finishedBundle(at: "2026-11-18T10-00-00-000Z", finishedAt: Date(timeIntervalSince1970: 1_794_996_000))

        let setup = await Run("setup", "--app-scheme", "App", "--finished-test-bundles", "drop", context: context)
        #expect(setup.status == 0, "\(setup.errors)")
        #expect(setup.output.contains("xcrew: after each test run, the older test runs' own test products are deleted and the newest kept, in every checkout of this repository"))

        let run = await Run("tidy", context: context)
        #expect(run.text == #"{"dropped":1}"#)
        #expect(!FileManager.default.fileExists(atPath: bundle.path))
        #expect(FileManager.default.fileExists(atPath: newest.path))
    }

    @Test func setupWithoutTheOptionKeepsTheChoice() async throws {
        _ = await Run("setup", "--app-scheme", "App", "--finished-test-bundles", "drop", context: context)
        let again = await Run("setup", "--app-scheme", "App", context: context)

        #expect(!again.output.contains { $0.contains("test products") })
        #expect(await FinishedTestBundlesChoice.read(for: project, using: runner) == .drop)
    }

    @Test func setupRefusesAnotherValueBeforeWritingAnything() async {
        let run = await Run("setup", "--app-scheme", "App", "--finished-test-bundles", "sometimes", context: context)

        #expect(run.status == 64)
        #expect(run.errors == ["--finished-test-bundles takes keep or drop"])
        #expect(!project.hasMobileBuildMCPConfig)
    }

    @Test func outsideGitSetupRefusesTheOptionBeforeWritingAnythingAndTheFormOffersNone() async throws {
        let outside = CheckContext.fake(FakeRunner.simulators(["iPhone 18"]), project: project)

        let run = await Run("setup", "--app-scheme", "App", "--finished-test-bundles", "drop", context: outside)
        #expect(run.status != 0)
        #expect(run.errors == ["the choice of what to do with finished test bundles is kept in the repository's git folder, and this project isn't in git"])
        #expect(!project.hasMobileBuildMCPConfig)

        let choices = await Run("setup", "--choices", context: outside)
        #expect(try JSONDecoder().decode(SetupChoices.self, from: Data(choices.text.utf8)).finishedTestBundles == nil)
    }

    /// The choice is the repository's, so a linked worktree records it too, for every checkout.
    @Test func aLinkedWorktreeRecordsTheChoiceForTheWholeRepository() async throws {
        let main = Project.temporary(containing: ["App.xcodeproj"])
        main.write(SetupWorktreeTests.mainConfig, to: ".mobilebuildmcp/config.yaml")
        let (_, worktree) = SetupWorktreeTests.worktree(main: main)

        let run = await Run("setup", "--worktree", "--no-simulator", "--finished-test-bundles", "drop", context: worktree)

        #expect(run.status == 0, "\(run.errors)")
        #expect(run.output.contains("xcrew: after each test run, the older test runs' own test products are deleted and the newest kept, in every checkout of this repository"))
        #expect(try String(contentsOf: main.root.appending(path: ".git/xcrew/finished-test-bundles"), encoding: .utf8) == "drop\n")
    }

    @Test func theFormReadsTheChoice() async throws {
        let before = await Run("setup", "--choices", context: context)
        #expect(try JSONDecoder().decode(SetupChoices.self, from: Data(before.text.utf8)).finishedTestBundles == .keep)

        _ = await Run("setup", "--app-scheme", "App", "--finished-test-bundles", "drop", context: context)

        let after = await Run("setup", "--choices", context: context)
        #expect(try JSONDecoder().decode(SetupChoices.self, from: Data(after.text.utf8)).finishedTestBundles == .drop)
    }
}
