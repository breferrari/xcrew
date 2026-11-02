import Foundation

import XcrewCore

/// The mod's reader for a finished build, test or run call: the server's result text on stdin,
/// the report as JSON on stdout.
struct ReportCommand: Command {
    let name = "report"
    let valuedOptions: Set<String> = ["server", "kind", "log", "tool", "since"]
    let flags: Set<String> = ["error", "repeated", "notification", "passed", "launches"]
    let usage = [
        "report --server S --kind K [--error] [--repeated] [--passed] [--notification [--launches]] [--log PATH | --tool T --since MS]   (mod) read a build, test or run result on stdin; print its report as JSON; --repeated reads each repeated test's runs; --passed lists the tests the results give as passed, for the ledger; --notification reads the result in a background task's notification; --log reads a MobileBuildMCP run's log and the result bundle it names, after the notification when both are given, --launches its verdict as a call's that installs and launches after its build, whose build's success is no outcome; --tool and --since (the call's start, in milliseconds) find the run's log when no --log is given, the first that tool's server named since, for its scheme, and after a notification for its outcome too",
    ]

    func run(_ invocation: Invocation) async throws -> Int32 {
        guard let server = invocation.arguments["server"].flatMap(Server.init(rawValue:)) else {
            throw UsageError(description: "report needs --server MobileBuildMCP or xcode")
        }
        guard let kind = invocation.arguments["kind"].flatMap(Report.Kind.init(rawValue:)) else {
            throw UsageError(description: "report needs --kind build, test or run")
        }
        let machine = invocation.context.machine.pooled()
        let repeated = invocation.arguments.has("repeated")
        let listsPassed = invocation.arguments.has("passed")
        var report: Report
        let given = invocation.arguments["log"]
        var found: String?
        if given == nil, let tool = invocation.arguments["tool"] {
            guard let since = invocation.arguments["since"].flatMap(Double.init).flatMap({ Int(exactly: $0.rounded(.down)) }) else { throw UsageError(description: "report --tool needs --since, in milliseconds") }
            found = await RunLog.first(tool: tool, since: since, project: invocation.context.project.root, machine: machine)?.path
        }
        let log = given ?? found
        if invocation.arguments.has("notification") {
            let text = String(decoding: await invocation.standardInput(), as: UTF8.self)
            report = await Report.make(kind: kind, notification: text, log: log, launches: invocation.arguments.has("launches"), server: server, home: machine.home.path, runner: machine.runner, repeated: repeated, listsPassed: listsPassed, project: invocation.context.project, machine: machine)
        } else if let given {
            report = await Report.make(kind: kind, log: RunLog.end(ofLogAt: given), runner: machine.runner, repeated: repeated, listsPassed: listsPassed)
        } else {
            let output = ToolOutput(text: String(decoding: await invocation.standardInput(), as: UTF8.self), server: server, isError: invocation.arguments.has("error"))
            report = await Report.make(kind: kind, output: output, home: machine.home.path, runner: machine.runner, repeated: repeated, listsPassed: listsPassed, project: invocation.context.project, machine: machine)
        }
        if let log { report.scheme = RunLog.scheme(ofLogAt: URL(fileURLWithPath: log)) }
        if let cut = (invocation.context.machine.runner as? DeadlineRunner).flatMap({ DeadlineRunner.leftOut($0.cut) }) { report.notes.append(cut) }
        let encoded = try JSONEncoder.sorted.encode(report)
        invocation.print(String(decoding: encoded, as: UTF8.self))
        return 0
    }
}

extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
