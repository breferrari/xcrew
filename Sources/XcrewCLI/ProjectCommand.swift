import Foundation

import XcrewCore

/// What kind of project this is, for the mod's `XcodeWrite` guard: whether a generator writes its project files.
struct ProjectCommand: Command {
    let name = "project"
    let usage = [
        "project   (mod) whether Tuist or XcodeGen generates this project, as JSON",
    ]

    struct Answer: Codable, Equatable {
        let isGenerated: Bool
    }

    func run(_ invocation: Invocation) async throws -> Int32 {
        let answer = Answer(isGenerated: invocation.context.project.isGenerated)
        invocation.print(String(decoding: try JSONEncoder.sorted.encode(answer), as: UTF8.self))
        return 0
    }
}
