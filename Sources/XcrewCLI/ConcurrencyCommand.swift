import Foundation
import XcrewCore

/// A build's Swift concurrency diagnostics by the compiler's own groups and by module, from its log: MobileBuildMCP's
/// newest build or test log for the project, as `xcrew why` reads, or the one `--log` names.
struct ConcurrencyCommand: Command {
    let name = "concurrency"
    let valuedOptions: Set<String> = ["log"]
    let flags: Set<String> = ["changed", "json"]
    let usage = ["concurrency [--log <file>] [--changed] [--json]   a build's Swift concurrency diagnostics by compiler group and module, from MobileBuildMCP's newest build log or <file>; --changed only those in lines the branch changed"]

    func run(_ invocation: Invocation) async throws -> Int32 {
        let context = invocation.context
        guard let log = invocation.arguments["log"] ?? RunLog.newestBuild(project: context.project.root, home: context.machine.home)?.path else {
            invocation.print(WhyCommand.noLog)
            return 1
        }
        let docs = await Xcodes.selected(on: context.machine).map { ConcurrencyGroups.docs(in: URL(fileURLWithPath: $0.path)) }
        let report: ConcurrencyReport
        do {
            report = try await ConcurrencyReport.read(log: URL(fileURLWithPath: log), project: context.project, groups: .read(docs: docs), onlyChanged: invocation.arguments.has("changed"), using: context.runner)
        } catch {
            invocation.print("xcrew: couldn't read \(log)")
            return 1
        }
        if invocation.arguments.has("json") {
            invocation.print(String(decoding: try JSONEncoder.sorted.encode(report), as: UTF8.self))
        } else {
            words(report, changedOnly: invocation.arguments.has("changed")).forEach(invocation.print)
        }
        return 0
    }

    func words(_ report: ConcurrencyReport, changedOnly: Bool) -> [String] {
        let plural = { (count: Int, word: String) in "\(count) \(word)\(count == 1 ? "" : "s")" }
        let scope = changedOnly ? " in lines the branch changed" : ""
        var lines: [String] = []
        if report.count == 0 {
            lines.append("No Swift concurrency diagnostics\(scope).")
        } else {
            let errors = report.errors > 0 ? " (\(plural(report.errors, "error")))" : ""
            lines.append("\(plural(report.count, "Swift concurrency diagnostic"))\(errors)\(scope) in \(plural(report.modules.count, "module")):")
            for group in report.groups {
                let modules = group.modules.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
                lines.append("  \(group.name) \(group.count)\(group.title.map { " (\($0))" } ?? ""): \(modules)")
            }
        }
        if !changedOnly, let changed = report.inChangedLines, report.count > 0 {
            lines.append("\(changed) of them \(changed == 1 ? "is" : "are") in lines this branch changed.")
        }
        if report.ungrouped > 0 {
            lines.append("\(plural(report.ungrouped, "diagnostic")) \(report.ungrouped == 1 ? "carries" : "carry") no compiler group, so \(report.ungrouped == 1 ? "it isn't" : "they aren't") counted: only \(report.ungrouped == 1 ? "its" : "their") text would say what \(report.ungrouped == 1 ? "it's" : "they're") about.")
        }
        lines.append(report.groupsFromDocs
            ? "Which groups are about concurrency comes from the selected Xcode's own group docs."
            : "Which groups are about concurrency comes from their names: the selected Xcode's group docs weren't found.")
        return lines
    }
}
