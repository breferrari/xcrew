import Foundation

import XcrewCore

/// The mod's reader for a finished build, test or run call: the server's result text on stdin,
/// the report as JSON on stdout.
struct ReportCommand: Command {
    let name = "report"
    let valuedOptions: Set<String> = ["server", "kind"]
    let usage = [
        "report --server S --kind K [--error]   (mod) read a build, test or run result on stdin; print its report as JSON",
    ]

    func run(_ invocation: Invocation) async throws -> Int32 {
        guard let server = invocation.arguments["server"] else { throw UsageError(description: "report needs --server") }
        guard let kind = invocation.arguments["kind"].flatMap(Report.Kind.init(rawValue:)) else {
            throw UsageError(description: "report needs --kind build, test or run")
        }
        let output = ToolOutput(text: String(decoding: invocation.standardInput(), as: UTF8.self), isError: invocation.arguments.has("error"))
        let machine = invocation.context.machine
        let report = await Report.make(server: server, kind: kind, output: output, home: machine.home.path, runner: machine.runner)
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
