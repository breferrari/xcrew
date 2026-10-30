import Foundation

import XcrewCore

/// Why the last build failed, when the cause is the Mac: from MobileBuildMCP's newest build or test log for the
/// project, a log named, or a server's result on stdin.
struct WhyCommand: Command {
    let name = "why"
    let valuedOptions: Set<String> = ["log", "server"]
    let usage = [
        "why [--log <file>] [--server S]   why the last build failed, when the cause is this Mac, and the fix: from MobileBuildMCP's newest build log, a log, or a result on stdin",
    ]

    static let nothing = "xcrew: nothing on this Mac explains the failure; its errors are the code's to fix"
    static let passed = "xcrew: the build this log is from reported no errors"
    static let noLog = "xcrew: MobileBuildMCP has no build or test log for this project yet; pass --log <file> for another"

    func run(_ invocation: Invocation) async throws -> Int32 {
        let context = invocation.context
        let note: String?
        if let named = invocation.arguments["server"] {
            guard let server = Server(rawValue: named) else { throw UsageError(description: "why --server needs MobileBuildMCP or xcode") }
            let output = ToolOutput(text: String(decoding: await invocation.standardInput(), as: UTF8.self), server: server, isError: true)
            note = await Why.note(for: output, home: context.machine.home.path, project: context.project, runner: context.runner)
        } else {
            guard let log = invocation.arguments["log"] ?? RunLog.newestBuild(project: context.project.root, home: context.machine.home)?.path else {
                invocation.print(Self.noLog)
                return 1
            }
            guard let data = FileManager.default.contents(atPath: log) else {
                invocation.print("xcrew: couldn't read \(log)")
                return 1
            }
            let errors = BuildLog.errors(in: String(decoding: data, as: UTF8.self))
            guard !errors.isEmpty else {
                invocation.print(Self.passed)
                return 0
            }
            note = await Why.note(for: FailureEvidence(errors: errors, project: context.project, runner: context.runner) { log })
        }
        invocation.print(note ?? Self.nothing)
        return 0
    }
}
