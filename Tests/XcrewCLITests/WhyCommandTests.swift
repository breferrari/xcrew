import Foundation
import Testing
@testable import XcrewCLI
@testable import XcrewCore
import XcrewTestSupport

/// `xcrew why`: the cause of the last build's failure when it's the Mac, from MobileBuildMCP's newest build log, a log
/// named, or a result on stdin.
@Suite struct WhyCommandTests {
    /// xcodebuild's log for an iPhone name no simulator has (the test bed's `captures/environment/simulator-missing.log`,
    /// trimmed).
    static let missingSimulator = """
        Command line invocation:
            /usr/bin/xcodebuild -project /testbed/captures/environment/App.xcodeproj -scheme App -derivedDataPath /testbed/DerivedData -destination "platform=iOS Simulator,name=iPhone 1,OS=latest" build

        xcodebuild: error: Unable to find a device matching the provided destination specifier:
        \t\t{ platform:iOS Simulator, OS:latest, name:iPhone 1 }

        \tThe requested device could not be found because no available devices matched the request.

        """

    /// A log of the code's own error.
    static let compileError = "/testbed/captures/environment/App/ContentView.swift:13:9: error: cannot convert value of type 'String' to specified type 'Int'\n"

    func context(_ project: Project = .temporary()) -> CheckContext {
        .fake(.simulators(["iPhone 17"]), project: project)
    }

    /// A log named: the Mac's cause and its fix, or, for the code's own errors, that nothing on the Mac explains them.
    @Test(arguments: [
        (missingSimulator, "xcrew: this build failed because of the Mac, not the code: no simulator here is named iPhone 1, which the build asked for. /xcrew:setup writes the profiles again with simulators that are installed"),
        (compileError, "xcrew: nothing on this Mac explains the failure; its errors are the code's to fix"),
    ])
    func aLogNamedIsRead(log: String, answer: String) async {
        let project = Project.temporary()
        project.write(log, to: "build.log")
        let run = await Run("why", "--log", project.root.appending(path: "build.log").path, context: context(project))
        #expect(run.status == 0)
        #expect(run.text == answer)
    }

    /// Without a log named, the newest build or test log MobileBuildMCP wrote for this project.
    @Test func theNewestBuildLogIsReadWhenNoneIsNamed() async throws {
        let project = Project.temporary()
        let context = context(project)
        let logs = context.machine.home.appending(path: "Library/Developer/MobileBuildMCP/workspaces/\(RunLog.workspaceKey(root: project.root.path))/logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try Self.compileError.write(to: logs.appending(path: "build_sim_1_pid1_a.log"), atomically: true, encoding: .utf8)
        try Self.missingSimulator.write(to: logs.appending(path: "build_sim_2_pid1_b.log"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: logs.appending(path: "build_sim_1_pid1_a.log").path)
        let run = await Run("why", context: context)
        #expect(run.text.hasPrefix("xcrew: this build failed because of the Mac, not the code: no simulator here is named iPhone 1"))
    }

    /// An earlier failure's log is another server's when MobileBuildMCP has restarted, or in another session.
    @Test func anotherServersLogIsRead() async throws {
        let project = Project.temporary()
        var responses = FakeSession.responses(serving: project)
        responses["xcrun simctl list devices available --json"] = FakeRunner.simulators(["iPhone 17"]).responses["xcrun simctl list devices available --json"]
        let context = CheckContext.fake(FakeRunner(responses: responses), project: project, processID: FakeSession.doctor)
        let logs = context.machine.home.appending(path: "Library/Developer/MobileBuildMCP/workspaces/\(RunLog.workspaceKey(root: project.root.path))/logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try Self.missingSimulator.write(to: logs.appending(path: "build_sim_1_pid999_a.log"), atomically: true, encoding: .utf8)
        let run = await Run("why", context: context)
        #expect(run.text.hasPrefix("xcrew: this build failed because of the Mac, not the code: no simulator here is named iPhone 1"))
    }

    /// The newest log is a build that passed: there's no failure to explain.
    @Test func aLogWithNoErrorsSaysTheBuildPassed() async {
        let project = Project.temporary()
        project.write("Build succeeded\n** BUILD SUCCEEDED **\n", to: "build.log")
        let run = await Run("why", "--log", project.root.appending(path: "build.log").path, context: context(project))
        #expect(run.status == 0)
        #expect(run.text == "xcrew: the build this log is from reported no errors")
    }

    /// A log isn't always valid UTF-8: a script phase can print anything.
    @Test func aLogWithAnInvalidByteIsRead() async throws {
        let project = Project.temporary()
        let log = project.root.appending(path: "build.log")
        try (Data("\u{FF}garbage from a script\n".utf8) + Data([0xFF, 0x0A]) + Data(Self.missingSimulator.utf8)).write(to: log)
        let run = await Run("why", "--log", log.path, context: context(project))
        #expect(run.text.hasPrefix("xcrew: this build failed because of the Mac, not the code: no simulator here is named iPhone 1"))
    }

    @Test func aResultOnStdinIsRead() async {
        let result = "\n🔨 Build\n\nErrors (1):\n\n  ✗ Unable to find a device matching the provided destination specifier:\n    { platform:iOS Simulator, OS:latest, name:iPhone 1 }\n\n❌ Build failed. (⏱️ 61.2s)\n"
        let run = await Run("why", "--server", "MobileBuildMCP", context: context(), stdin: result)
        #expect(run.text.hasPrefix("xcrew: this build failed because of the Mac, not the code: no simulator here is named iPhone 1"))
    }

    @Test func withoutALogItSaysWhereToLook() async {
        let run = await Run("why", context: context())
        #expect(run.status == 1)
        #expect(run.text == "xcrew: MobileBuildMCP has no build or test log for this project yet; pass --log <file> for another")
    }
}
