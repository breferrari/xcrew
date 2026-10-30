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
    let flags: Set<String> = ["list", "problems", "json"]
    let usage = [
        "doctor [--check ID]   run the health checks (exit: 1 failed, 2 warned, 3 every check skipped, else 0)",
        "doctor --list         list the check ids",
        "doctor --problems     only what failed or warned, worst first, or \"No problems.\", then the checks kept off the prompt; nothing outside an Apple-platform project (exit 0)",
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
        // The mod shows these on the band; outside an Apple project every project check would fail.
        let onlyProblems = invocation.arguments.has("problems")
        if onlyProblems, !invocation.context.project.isApplePlatformProject { return 0 }
        // It runs at session start and after prompts, so it leaves out checks that call the network, and the results the
        // line above the prompt doesn't show.
        let checks = Doctor.checks.filter { !onlyProblems || !$0.reachesNetwork }
        let ran = await Doctor.run(checks, in: invocation.context)
        let problems = onlyProblems ? Doctor.problems(ran) : []
        let entries = onlyProblems ? problems.filter { !$0.result.isOffThePrompt } : ran
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
        let kept = problems.filter(\.result.isOffThePrompt).map(\.check.id)
        (onlyProblems ? Doctor.problemsText(lines: lines, kept: kept) : lines).forEach(invocation.print)
        return onlyProblems ? 0 : Doctor.worst(entries).rawValue
    }
}
