import Foundation

import XcrewCore

/// Saves the project card the mod builds, for the session-start hook to print (`ProjectCard`).
struct CardCommand: Command {
    let name = "card"
    let flags: Set<String> = ["save"]
    let usage = ["card --save   (mod) save this folder's and branch's project card, from JSON on stdin"]

    func run(_ invocation: Invocation) async throws -> Int32 {
        guard invocation.arguments.has("save") else { throw UsageError(description: "card needs --save") }
        guard let entry = try? JSONDecoder().decode(ProjectCard.Entry.self, from: await invocation.standardInput()) else {
            throw UsageError(description: "card --save reads a card as JSON on stdin")
        }
        ProjectCard.save(entry, on: invocation.context.machine)
        return 0
    }
}
