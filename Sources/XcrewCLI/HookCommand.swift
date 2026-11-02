import Foundation
import XcrewCore

/// Entry points for Claude Code command hooks. Each reads the event on stdin and prints a reply
/// only when it has something to say.
struct HookCommand: Command {
    let name = "hook"
    let takesWords = true
    let usage = [
        "hook session-start   (hook) routing rules and what this project still lacks",
        "hook session-end     (hook) forgets what the ended session reported",
    ]

    func run(_ invocation: Invocation) async throws -> Int32 {
        let hook = invocation.arguments.positional.first
        guard hook == "session-start" || hook == "session-end" else {
            throw UsageError(description: "unknown hook '\(hook ?? "")'")
        }
        let event = HookEvent(json: await invocation.standardInput())
        let machine = invocation.context.machine
        if hook == "session-end" {
            if let session = event.session { SessionStamp.remove(session, on: machine) }
            return 0
        }
        // Which version's rules this session was given, for the doctor to compare with the running one.
        if let session = event.session { SessionStamp.record(session, on: machine, .briefing, XcrewVersion.current) }
        let project = event.cwd.map { Project(root: URL(fileURLWithPath: $0, isDirectory: true), home: invocation.context.machine.home) } ?? invocation.context.project
        let routing = (try? String(contentsOf: Self.pluginRoot(machine).appending(path: "context/routing.md"), encoding: .utf8)) ?? ""
        if let text = await SessionBriefing(project: project, machine: machine).text(routing: routing) {
            invocation.print(HookReply(event: event, context: text).json)
        }
        return 0
    }

    /// Claude Code sets CLAUDE_PLUGIN_ROOT for plugin hooks; bin/xcrew sets XCREW_ROOT.
    static func pluginRoot(_ machine: Machine) -> URL {
        URL(fileURLWithPath: machine.value("CLAUDE_PLUGIN_ROOT") ?? machine.value("XCREW_ROOT") ?? ".")
    }
}
