import Foundation

/// The rules this session's start hook gave Claude are the running xcrew's: a plugin updated in an open session, even
/// after `/reload-plugins`, keeps the old ones until Claude Code restarts.
struct BriefingCurrentCheck: Check {
    let id = "xcrew/briefing-current"
    let title = "This session has the running xcrew's rules"

    func run(_ context: CheckContext) async -> CheckResult {
        guard let session = SessionStamp.session(on: context.machine) else { return .skip("not run from a Claude Code session") }
        guard let briefing = SessionStamp.read(session, on: context.machine)?.briefing else { return .skip("this session's start hook hasn't reported") }
        let running = XcrewVersion.current
        guard briefing == running else {
            return .warn("this session's rules are xcrew \(briefing)'s, and xcrew \(running) is running: restart Claude Code to load \(running)'s")
        }
        return .pass("xcrew \(running)'s")
    }
}
