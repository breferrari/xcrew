import Foundation

import XcrewCore

/// The mod's reader for a tool's result that no build, test or run report reads: the result on stdin, the notes Claude
/// reads beside it as JSON.
struct NoteCommand: Command {
    let name = "note"
    let valuedOptions: Set<String> = ["server"]
    let flags: Set<String> = ["error"]
    let usage = ["note --server S [--error]   (mod) the notes for a tool's result on stdin, as JSON"]

    struct Answer: Codable {
        let notes: [String]
    }

    func run(_ invocation: Invocation) async throws -> Int32 {
        guard let server = invocation.arguments["server"].flatMap(Server.init(rawValue:)) else {
            throw UsageError(description: "note needs --server MobileBuildMCP or xcode")
        }
        let output = ToolOutput(text: String(decoding: await invocation.standardInput(), as: UTF8.self), server: server, isError: invocation.arguments.has("error"))
        invocation.print(String(decoding: try JSONEncoder.sorted.encode(Answer(notes: ClosedConnection.notes(for: output))), as: UTF8.self))
        return 0
    }
}
