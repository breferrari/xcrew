import Foundation
import XcrewCore

/// `xcrew space`: what MobileBuildMCP and Xcode keep on this Mac, each part with the command that would reclaim it
/// (`Space`). It deletes nothing, and walks folders, so it runs only when asked.
struct SpaceCommand: Command {
    let name = "space"
    let flags: Set<String> = ["json"]
    let usage = ["space [--json]   what MobileBuildMCP and Xcode keep on this Mac, and the command that would reclaim each part; deletes nothing"]

    func run(_ invocation: Invocation) async throws -> Int32 {
        let report = await Space.report(project: invocation.context.project, machine: invocation.context.machine)
        if invocation.arguments.has("json") {
            invocation.print(String(decoding: try JSONEncoder.sorted.encode(report), as: UTF8.self))
        } else {
            invocation.print(report.text.trimmingCharacters(in: .newlines))
        }
        return 0
    }
}
