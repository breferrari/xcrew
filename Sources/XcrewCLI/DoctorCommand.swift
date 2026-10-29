import Foundation

import XcrewCore

struct DoctorCommand: Command {
    struct JSONLine: Codable, Equatable {
        let status: String
        let id: String
        let message: String
    }

    let name = "doctor"
    let valuedOptions: Set<String> = ["check"]
    let usage = [
        "doctor [--check ID]   run the health checks (exit: 0 ok, 1 failed, 2 warned, 3 skipped)",
        "doctor --list         list the check ids",
        "doctor --problems     only what failed or warned, or \"No problems.\"; nothing outside an Apple-platform project (exit 0)",
        "doctor --json         the same, as JSON: each check's status, id and message (the mod reads it)",
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
        if invocation.arguments.has("json") {
            let lines = entries.map { JSONLine(status: $0.result.status.tag.lowercased(), id: $0.check.id, message: $0.result.message) }
            invocation.print(String(decoding: try JSONEncoder.sorted.encode(lines), as: UTF8.self))
            return onlyProblems ? 0 : Doctor.worst(entries).rawValue
        }
        let width = entries.map(\.check.id.count).max() ?? 0
        let lines = entries.map { entry in
            let tag = entry.result.status.tag.padding(toLength: 4, withPad: " ", startingAt: 0)
            let id = entry.check.id.padding(toLength: width, withPad: " ", startingAt: 0)
            return "\(tag)  \(id)  \(entry.result.message)"
        }
        (onlyProblems ? Doctor.problemsText(lines: lines) : lines).forEach(invocation.print)
        return onlyProblems ? 0 : Doctor.worst(entries).rawValue
    }
}
