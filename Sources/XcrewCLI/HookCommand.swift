import Foundation
import XcrewCore

/// Entry points for Claude Code command hooks. Each reads the event on stdin and prints a reply
/// only when it has something to say.
struct HookCommand: Command {
    let name = "hook"
    let usage = [
        "hook session-start   (hook) routing rules and what this project still lacks",
    ]

    func run(_ invocation: Invocation) async throws -> Int32 {
        guard invocation.arguments.positional.first == "session-start" else {
            throw UsageError(description: "unknown hook '\(invocation.arguments.positional.first ?? "")'")
        }
        let event = HookEvent(json: invocation.standardInput())
        let machine = invocation.context.machine
        let project = event.cwd.map { Project(root: URL(fileURLWithPath: $0, isDirectory: true), home: invocation.context.machine.home) } ?? invocation.context.project
        let routing = (try? String(contentsOf: Self.pluginRoot(machine).appending(path: "context/routing.md"), encoding: .utf8)) ?? ""
        if let text = SessionBriefing(project: project, machine: machine).text(routing: routing) {
            invocation.print(HookReply(event: event, context: text).json)
        }
        return 0
    }

    /// Claude Code sets CLAUDE_PLUGIN_ROOT for plugin hooks; bin/xcrew sets XCREW_ROOT.
    static func pluginRoot(_ machine: Machine) -> URL {
        URL(fileURLWithPath: machine.value("CLAUDE_PLUGIN_ROOT") ?? machine.value("XCREW_ROOT") ?? ".")
    }
}
