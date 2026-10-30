import Foundation
import Testing
@testable import XcrewCLI
@testable import XcrewCore
import XcrewTestSupport

/// `xcrew setup --worktree`: a linked worktree's MobileBuildMCP config, taken from its main checkout's.
@Suite struct SetupWorktreeTests {
    /// The main checkout's config: a profile with an absolute DerivedData, outside the checkout, and one written from
    /// the root.
    static let mainConfig = """
        schemaVersion: 1
        sessionDefaultsProfiles:
          unit:
            projectPath: 'App.xcodeproj'
            scheme: 'App'
            derivedDataPath: '/Users/someone/DerivedData/App'
        activeSessionDefaultsProfile: unit

        """

    /// A worktree whose git says its main checkout is `main`, or a main checkout when `main` is nil.
    static func worktree(main: Project?) -> (Project, CheckContext) {
        let worktree = Project.temporary(containing: ["App.xcodeproj"])
        var runner = FakeRunner()
        if let main { runner.linkWorktree(worktree, to: main) } else {
            runner.responses["git -C \(worktree.root.path) rev-parse --path-format=absolute --git-dir --git-common-dir --show-prefix"] = CommandResult(status: 0, stdout: "\(worktree.root.path)/.git\n\(worktree.root.path)/.git\n\n")
        }
        return (worktree, .fake(runner, project: worktree))
    }

    static func config(_ project: Project) -> String? {
        try? String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8)
    }

    @Test func aWorktreeTakesTheMainCheckoutsConfig() async {
        let main = Project.temporary(containing: ["App.xcodeproj"])
        main.write(Self.mainConfig, to: ".mobilebuildmcp/config.yaml")
        let (worktree, context) = Self.worktree(main: main)
        let run = await Run("setup", "--worktree", context: context)
        #expect(run.status == 0)
        #expect(Self.config(worktree) == Self.mainConfig.replacingOccurrences(of: "    derivedDataPath: '/Users/someone/DerivedData/App'\n", with: ""))
        #expect(run.output == [
            "xcrew: wrote .mobilebuildmcp/config.yaml from the main checkout's (\(main.root.path)); restart Claude Code so MobileBuildMCP reads it",
            "xcrew: left out derivedDataPath /Users/someone/DerivedData/App, which the main checkout uses: this worktree's builds go in a DerivedData of its own",
        ])
        // xcrew wrote it: a later setup may replace it, and the doctor asks for a restart.
        #expect(ConfigWriter.keeping(worktree) == nil)
    }

    /// Like setup, it keeps `.mobilebuildmcp/` out of git, in the exclude file every worktree of the repository shares.
    @Test func theConfigIsKeptOutOfGit() async {
        let main = Project.temporary(containing: ["App.xcodeproj"])
        main.write(Self.mainConfig, to: ".mobilebuildmcp/config.yaml")
        main.write("", to: ".git/info/exclude")
        let worktree = Project.temporary(containing: ["App.xcodeproj"])
        var runner = FakeRunner(responses: ["git -C \(worktree.root.path) rev-parse --git-path info/exclude": CommandResult(status: 0, stdout: "\(main.root.path)/.git/info/exclude\n")])
        runner.linkWorktree(worktree, to: main)
        let run = await Run("setup", "--worktree", context: .fake(runner, project: worktree))
        #expect(run.output.last == "xcrew: kept .mobilebuildmcp/ out of git (in .git/info/exclude, which isn't committed)", "\(run.output)")
        #expect((try? String(contentsOf: main.root.appending(path: ".git/info/exclude"), encoding: .utf8)) == "/.mobilebuildmcp/\n")
    }

    @Test func aWorktreeConfigEditedSinceIsKept() async {
        let main = Project.temporary(containing: ["App.xcodeproj"])
        main.write(Self.mainConfig, to: ".mobilebuildmcp/config.yaml")
        let (worktree, context) = Self.worktree(main: main)
        _ = await Run("setup", "--worktree", context: context)
        worktree.write("schemaVersion: 1\n# mine\n", to: ".mobilebuildmcp/config.yaml")
        let run = await Run("setup", "--worktree", context: context)
        #expect(Self.config(worktree) == "schemaVersion: 1\n# mine\n")
        #expect(run.output == ["xcrew: .mobilebuildmcp/config.yaml was edited after xcrew wrote it; left as is (--force replaces it, keeping a backup)"])
    }

    @Test func theMainCheckoutWithoutAConfigIsSaidSo() async {
        let main = Project.temporary(containing: ["App.xcodeproj"])
        let (_, context) = Self.worktree(main: main)
        let run = await Run("setup", "--worktree", context: context)
        #expect(run.status == 1)
        #expect(run.output == ["xcrew: the main checkout (\(main.root.path)) has no .mobilebuildmcp/config.yaml; xcrew setup there, or plain xcrew setup here, writes one"])
    }

    /// Its config is the main checkout's, so the options that answer setup's questions have no place beside it.
    @Test func anotherOptionIsAUsageError() async {
        let main = Project.temporary(containing: ["App.xcodeproj"])
        main.write(Self.mainConfig, to: ".mobilebuildmcp/config.yaml")
        let (worktree, context) = Self.worktree(main: main)
        let run = await Run("setup", "--worktree", "--test-scheme", "AppTests", context: context)
        #expect(run.status == 64)
        #expect(run.errors == ["setup --worktree takes no option but --force: the profiles are the main checkout's"])
        #expect(Self.config(worktree) == nil)
    }

    @Test func outsideAWorktreeItIsAUsageError() async {
        let (_, context) = Self.worktree(main: nil)
        let run = await Run("setup", "--worktree", context: context)
        #expect(run.status == 64)
        #expect(run.errors == ["setup --worktree runs in a linked git worktree; this is a main checkout, or not in git"])
    }
}
