import Foundation

import XcrewCore

struct DoctorCommand: Command {
    let name = "doctor"
    let valuedOptions: Set<String> = ["check"]
    let usage = [
        "doctor [--check ID]   run the health checks (exit: 0 ok, 1 failed, 2 warned, 3 skipped)",
        "doctor --list         list the check ids",
        "doctor --problems     only what failed or warned, and nothing outside an Apple-platform project (exit 0)",
    ]

    func run(_ invocation: Invocation) async throws -> Int32 {
        if invocation.arguments.has("list") {
            Doctor.checks.forEach { invocation.print("\($0.id)\t\($0.title)") }
            return 0
        }
        if let id = invocation.arguments["check"] {
            guard let check = Doctor.check(id: id) else { throw UsageError(description: "unknown check '\(id)' (doctor --list)") }
            let result = await check.run(invocation.context)
            invocation.print(result.message)
            return result.status.rawValue
        }
        // The mod shows these at session start; outside an Apple project every project check would fail.
        let onlyProblems = invocation.arguments.has("problems")
        if onlyProblems, !invocation.context.project.isApplePlatformProject { return 0 }
        // It runs at every session start, so it leaves out checks that call the network.
        let checks = Doctor.checks.filter { !onlyProblems || !$0.reachesNetwork }
        let entries = await Doctor.run(checks, in: invocation.context)
            .filter { !onlyProblems || $0.result.status == .fail || $0.result.status == .warn }
        let width = entries.map(\.check.id.count).max() ?? 0
        for entry in entries {
            let tag = entry.result.status.tag.padding(toLength: 4, withPad: " ", startingAt: 0)
            let id = entry.check.id.padding(toLength: width, withPad: " ", startingAt: 0)
            invocation.print("\(tag)  \(id)  \(entry.result.message)")
        }
        return onlyProblems ? 0 : Doctor.worst(entries).rawValue
    }
}
