import Foundation

import XcrewCore

/// The mod's reader for a MobileBuildMCP session tool's text answer: the answer on stdin, what it says of the
/// profiles and the one in use as JSON, `{}` when it's in no shape xcrew knows.
struct SessionCommand: Command {
    let name = "session"
    let usage = ["session   (mod) a MobileBuildMCP session tool's text answer on stdin: its profiles, or the profile it activated, as JSON"]

    func run(_ invocation: Invocation) async throws -> Int32 {
        let answer = SessionAnswer.read(String(decoding: await invocation.standardInput(), as: UTF8.self))
        invocation.print(String(decoding: try JSONEncoder.sorted.encode(answer), as: UTF8.self))
        return 0
    }
}
