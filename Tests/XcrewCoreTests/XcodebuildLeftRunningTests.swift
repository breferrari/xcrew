import Foundation
import Testing

@testable import XcrewCore
import XcrewTestSupport

/// An xcodebuild still building the project after the call that started it: its session ended, or the call was stopped
/// while MobileBuildMCP's xcodebuild went on.
@Suite struct XcodebuildLeftRunningTests {
    static let destination = "platform=iOS Simulator,name=iPhone 17"
    static let build = "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild build -scheme App -destination \(destination) -derivedDataPath /Users/dev/Library/Developer/Xcode/DerivedData/App-abcdef"

    /// `ps` and `comm` for `lines` of (pid, ppid, etime, command, program), and each listed pid's working folder.
    static func runner(_ lines: [(Int32, Int32, String, String, String)], folders: [Int32: String]) -> FakeRunner {
        let ps = lines.map { "  \($0.0) \($0.1) \($0.2) \($0.3)" }.joined(separator: "\n") + "\n"
        let comm = lines.map { "  \($0.0) \($0.4)" }.joined(separator: "\n") + "\n"
        var responses: [String: CommandResult] = [
            "ps -axo pid=,ppid=,etime=,command=": .init(status: 0, stdout: ps),
            "ps -axo pid=,comm=": .init(status: 0, stdout: comm),
        ]
        let ids = folders.keys.sorted()
        let listed = ids.map { "p\($0)\nfcwd\nn\(folders[$0]!)\n" }.joined()
        responses["lsof -a -p \(ids.map(String.init).joined(separator: ",")) -d cwd -Fn"] = .init(status: 0, stdout: listed)
        return FakeRunner(responses: responses)
    }

    static func run(_ lines: [(Int32, Int32, String, String, String)], folders: [Int32: String], project: Project) async -> CheckResult {
        await XcodebuildLeftRunningCheck().run(.fake(runner(lines, folders: folders), project: project, processID: 600))
    }

    static let left = "an xcodebuild whose starter has exited still builds this project, holding its build folder: pid 900, for platform=iOS Simulator,name=iPhone 17, running 12 min. A call stopped partway leaves one once its session ends. Stopping it frees the folder: kill 900"

    @Test func anXcodebuildWhoseSessionEndedIsNamedWithHowToStopIt() async {
        let project = Project.temporary()
        let result = await Self.run([(900, 1, "12:05", Self.build, "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild")], folders: [900: project.root.path], project: project)
        #expect(result == .warn(Self.left))
        #expect(!result.isOffThePrompt)
    }

    /// MobileBuildMCP starts it through `xcrun`, which may stay as its parent.
    @Test func anXcodebuildUnderAnXcrunLeftRunningIsTheOne() async {
        let project = Project.temporary()
        let lines: [(Int32, Int32, String, String, String)] = [
            (899, 1, "12:06", "/usr/bin/xcrun xcodebuild build -scheme App", "/usr/bin/xcrun"),
            (900, 899, "12:05", Self.build, "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"),
        ]
        #expect(await Self.run(lines, folders: [900: project.root.path], project: project) == .warn(Self.left))
    }

    /// Its working folder may be elsewhere when the command names the project's workspace.
    @Test func anXcodebuildNamingTheProjectsWorkspaceIsTheProjects() async {
        let project = Project.temporary()
        let command = Self.build + " -workspace \(project.root.path)/App.xcworkspace"
        #expect(await Self.run([(900, 1, "12:05", command, "xcodebuild")], folders: [900: "/"], project: project) == .warn(Self.left))
    }

    /// A call still going and a call stopped partway look the same from outside, so both are said, off the prompt.
    @Test func anXcodebuildUnderTheProjectsMobileBuildMCPIsSaidBothWays() async {
        let project = Project.temporary()
        let lines: [(Int32, Int32, String, String, String)] = [
            (100, 1, "01:00:00", "claude", "claude"),
            (200, 100, "50:00", FakeSession.server, "node-runtime"),
            (900, 200, "12:05", Self.build, "xcodebuild"),
            (600, 1, "00:01", "/plugins/xcrew/.build/xcrew doctor", "xcrew"),
        ]
        let result = await Self.run(lines, folders: [900: project.root.path], project: project)
        #expect(result == .warn("an xcodebuild MobileBuildMCP started still builds this project, holding its build folder: pid 900, for platform=iOS Simulator,name=iPhone 17, running 12 min. A call stopped partway leaves its xcodebuild running; a call moved to the background is still building. Stopping it frees the folder: kill 900"))
        #expect(result.isOffThePrompt)
    }

    @Test func anXcodebuildFromATerminalIsntOne() async {
        let project = Project.temporary()
        let lines: [(Int32, Int32, String, String, String)] = [
            (800, 1, "01:00:00", "-zsh", "-zsh"),
            (900, 800, "12:05", Self.build, "xcodebuild"),
        ]
        #expect(await Self.run(lines, folders: [900: project.root.path], project: project) == .pass("no xcodebuild left running for this project"))
    }

    @Test func anXcodebuildLeftForAnotherProjectIsntThisOnes() async {
        let project = Project.temporary()
        #expect(await Self.run([(900, 1, "12:05", Self.build, "xcodebuild")], folders: [900: "/Users/dev/Other"], project: project) == .pass("no xcodebuild left running for this project"))
    }

    @Test func withoutTheProcessListTheCheckSkips() async {
        let result = await XcodebuildLeftRunningCheck().run(.fake(FakeRunner(), processID: 600))
        #expect(result == .skip("couldn't list the processes"))
    }
    static let none = CheckResult.pass("no xcodebuild left running for this project")

    /// A Claude Code killed outright can leave its MobileBuildMCP server running under launchd, with its xcodebuild.
    @Test func anXcodebuildUnderAServerWhoseSessionEndedIsOnThePrompt() async {
        let project = Project.temporary()
        let lines: [(Int32, Int32, String, String, String)] = [
            (200, 1, "50:00", FakeSession.server, "node-runtime"),
            (900, 200, "12:05", Self.build, "xcodebuild"),
        ]
        let result = await Self.run(lines, folders: [900: project.root.path], project: project)
        #expect(result == .warn(Self.left))
        #expect(!result.isOffThePrompt)
    }

    /// A worktree inside the project, as Claude Code's `--worktree` makes, is its own checkout with its own build folder.
    @Test func anXcodebuildOfAWorktreeInsideTheProjectIsntThisOnes() async {
        let project = Project.temporary()
        project.write("gitdir: /elsewhere\n", to: ".claude/worktrees/feature/.git")
        let command = Self.build + " -workspace \(project.root.path)/.claude/worktrees/feature/App.xcworkspace"
        #expect(await Self.run([(900, 1, "12:05", command, "xcodebuild")], folders: [900: project.root.path + "/.claude/worktrees/feature"], project: project) == Self.none)
    }

    /// The app may sit in a folder of the project, built from there with relative paths.
    @Test func anXcodebuildRunInAFolderOfTheProjectIsTheProjects() async {
        let project = Project.temporary(containing: ["ios"])
        let command = "/x/xcodebuild build -workspace App.xcworkspace -destination \(Self.destination)"
        #expect(await Self.run([(900, 1, "12:05", command, "xcodebuild")], folders: [900: project.root.path + "/ios"], project: project) == .warn(Self.left))
    }

    @Test func withoutTheXcodebuildsFoldersTheCheckSkips() async {
        let project = Project.temporary()
        let command = "/x/xcodebuild build -workspace App.xcworkspace"
        let runner = Self.runner([(900, 1, "12:05", command, "xcodebuild")], folders: [:])
        #expect(await XcodebuildLeftRunningCheck().run(.fake(runner, project: project, processID: 600)) == .skip("couldn't read the xcodebuilds' folders"))
    }

    /// An xcodebuild that only answers a question opens no build folder.
    @Test(arguments: ["-showBuildSettings", "-list", "-version", "-showdestinations"])
    func anXcodebuildAskingAQuestionIsntOne(_ question: String) async {
        let project = Project.temporary()
        let command = "/x/xcodebuild \(question) -workspace \(project.root.path)/App.xcworkspace"
        #expect(await Self.run([(900, 1, "12:05", command, "xcodebuild")], folders: [900: project.root.path], project: project) == Self.none)
    }

    /// Without `comm`, the xcrun that ran it is still known by its command.
    @Test func anXcrunWithoutItsProgramNameIsStillReadPast() async {
        let project = Project.temporary()
        let lines: [(Int32, Int32, String, String, String)] = [
            (899, 1, "12:06", "/usr/bin/xcrun xcodebuild build -scheme App", ""),
            (900, 899, "12:05", Self.build, ""),
        ]
        #expect(await Self.run(lines, folders: [900: project.root.path], project: project) == .warn(Self.left))
    }
}
