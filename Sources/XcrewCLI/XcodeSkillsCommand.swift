import Foundation

import XcrewCore

struct XcodeSkillsCommand: Command {
    let name = "xcode-skills"
    let takesWords = true
    let flags: Set<String> = ["list", "force"]
    let usage = [
        "xcode-skills [--list] [--force] [NAME...]   copy the agent skills this Xcode ships into .claude/skills",
        "                                  (all unless names are given; run again after an Xcode update)",
    ]

    func run(_ invocation: Invocation) async throws -> Int32 {
        guard let skills = await XcodeSkills.locate(using: invocation.context.runner) else {
            throw UsageError(description: "Xcode's agent plugin not found (needs Xcode 27 or later)")
        }
        if invocation.arguments.has("list") {
            skills.available.forEach(invocation.print)
            return 0
        }
        let report = try skills.copy(invocation.arguments.positional, to: invocation.context.project.skillsFolder, replacing: invocation.arguments.has("force"))
        if !report.copied.isEmpty {
            invocation.print("xcrew: copied \(report.copied.count) Xcode skills into .claude/skills: \(report.copied.joined(separator: ", "))")
        }
        if !report.kept.isEmpty {
            invocation.print("xcrew: kept the project's own \(report.kept.joined(separator: ", ")) (--force replaces them)")
        }
        return 0
    }
}
