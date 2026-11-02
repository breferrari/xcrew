import Foundation

import XcrewCore

/// The folders, among those named, that aren't there any more: the mod drops what it stored for a checkout that's gone,
/// as a worktree removed since, at a session's start.
struct GoneCommand: Command {
    let name = "gone"
    let takesWords = true
    let usage = [
        "gone <folder>...   (mod) the folders named that aren't there any more, as JSON",
    ]

    struct Answer: Codable, Equatable {
        let gone: [String]
    }

    func run(_ invocation: Invocation) async throws -> Int32 {
        let gone = invocation.arguments.positional.filter { !FileManager.default.fileExists(atPath: $0) }
        invocation.print(String(decoding: try JSONEncoder.sorted.encode(Answer(gone: gone)), as: UTF8.self))
        return 0
    }
}
