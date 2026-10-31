import Foundation
import XcrewCore

/// A build's Swift concurrency diagnostics by the compiler's own groups and by module, from its log: MobileBuildMCP's
/// newest build or test log for the project, as `xcrew why` reads, or the one `--log` names. Which groups are about
/// concurrency comes from the docs of the Xcode the log names, else the selected one.
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
        let selected = await Xcodes.selected(on: context.machine).map { URL(fileURLWithPath: $0.path) }
        let report: ConcurrencyReport
        do {
            report = try await ConcurrencyReport.read(log: URL(fileURLWithPath: log), project: context.project, groups: { named in .read(docs: (named ?? selected).map(ConcurrencyGroups.docs(in:))) }, onlyChanged: invocation.arguments.has("changed"), using: context.runner)
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
        let counted = Space.counted
        let scope = changedOnly && report.changeUnread == nil ? " in lines the branch changed" : ""
        var lines: [String] = []
        if let unread = report.changeUnread { lines.append("The branch's changed lines couldn't be read (\(unread)), so this is the whole log.") }
        if report.count == 0 {
            lines.append("No Swift concurrency diagnostics\(scope).")
        } else {
            let errors = report.errors > 0 ? " (\(counted(report.errors, "error")))" : ""
            lines.append("\(counted(report.count, "Swift concurrency diagnostic"))\(errors)\(scope) in \(counted(report.modules.count, "module")):")
            for group in report.groups {
                let modules = group.modules.map { "\($0.name) \($0.count)" }.joined(separator: ", ")
                lines.append("  \(group.name) \(group.count)\(group.title.map { " (\($0))" } ?? ""): \(modules)")
            }
        }
        if !changedOnly, let changed = report.inChangedLines, report.count > 0 {
            lines.append("\(changed) of them \(changed == 1 ? "is" : "are") in lines this branch changed.")
        }
        if report.ungrouped > 0 {
            let one = report.ungrouped == 1
            lines.append("\(counted(report.ungrouped, "Swift diagnostic"))\(scope) \(one ? "carries" : "carry") no compiler group, so \(one ? "it isn't" : "they aren't") counted: only \(one ? "its" : "their") text would say what \(one ? "it's" : "they're") about.")
        }
        if let unread = report.projectUnread { lines.append("Modules come from the log's task headers alone: \(unread).") }
        lines.append(report.groupsFromDocs
            ? "Which groups are about concurrency comes from the group docs of the Xcode that built it\(report.xcode.map { " (\($0))" } ?? "")."
            : "Which groups are about concurrency comes from their names: no group docs were found for the Xcode that built it.")
        lines.append("A build that compiled only some files logs only theirs.")
        return lines
    }
}
