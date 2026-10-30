import Foundation

import XcrewCore

/// The mod's reader for a finished build, test or run call: the server's result text on stdin,
/// the report as JSON on stdout.
struct ReportCommand: Command {
    let name = "report"
    let valuedOptions: Set<String> = ["server", "kind"]
    let flags: Set<String> = ["error", "repeated"]
    let usage = [
        "report --server S --kind K [--error] [--repeated]   (mod) read a build, test or run result on stdin; print its report as JSON; --repeated reads each repeated test's runs",
    ]

    func run(_ invocation: Invocation) async throws -> Int32 {
        guard let server = invocation.arguments["server"].flatMap(Server.init(rawValue:)) else {
            throw UsageError(description: "report needs --server MobileBuildMCP or xcode")
        }
        guard let kind = invocation.arguments["kind"].flatMap(Report.Kind.init(rawValue:)) else {
            throw UsageError(description: "report needs --kind build, test or run")
        }
        let output = ToolOutput(text: String(decoding: await invocation.standardInput(), as: UTF8.self), server: server, isError: invocation.arguments.has("error"))
        let machine = invocation.context.machine
        let report = await Report.make(kind: kind, output: output, home: machine.home.path, runner: machine.runner, repeated: invocation.arguments.has("repeated"))
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
