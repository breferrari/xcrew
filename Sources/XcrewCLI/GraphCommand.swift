import Foundation
import XcrewCore

/// The workspace's modules, what each depends on, and where each import of one of them lands in that graph, as the
/// projects declare it; or, with `--owner`, the targets that build one file.
struct GraphCommand: Command {
    let name = "graph"
    let valuedOptions: Set<String> = ["owner"]
    let flags: Set<String> = ["json"]
    let usage = [
        "graph [--json]                 the modules, what each depends on, and where each import of one lands",
        "graph --owner <path> [--json]  the targets that build a file, its path from the project's root or absolute",
    ]

    func run(_ invocation: Invocation) async throws -> Int32 {
        let project = invocation.context.project
        let json = invocation.arguments.has("json")
        if let file = invocation.arguments["owner"] {
            let owners = FileOwners.of(file, in: project)
            if json {
                invocation.print(String(decoding: try JSONEncoder.sorted.encode(owners), as: UTF8.self))
            } else if let unread = owners.unread {
                invocation.print("The workspace couldn't be read: \(unread)")
            } else if owners.excepted == true {
                invocation.print("\(owners.file): an exception set changes its target membership, which this doesn't read\(owners.targets.isEmpty ? "" : " (listed in \(owners.targets.joined(separator: ", ")))")")
            } else {
                invocation.print("\(owners.file): \(owners.targets.isEmpty ? "no target builds it" : owners.targets.joined(separator: ", "))")
            }
            return owners.unread == nil ? 0 : 1
        }
        let graph = ModuleGraph.read(project)
        if json {
            invocation.print(String(decoding: try JSONEncoder.sorted.encode(graph), as: UTF8.self))
        } else {
            words(graph).forEach(invocation.print)
        }
        return graph.unread == nil ? 0 : 1
    }

    func words(_ graph: ModuleGraph) -> [String] {
        if let unread = graph.unread { return ["The workspace couldn't be read: \(unread)"] }
        var lines = ["\(Space.counted(graph.modules.count, "module")), as the projects declare them:"]
        for module in graph.modules {
            let dependencies = module.dependencies.isEmpty ? "depends on nothing" : "depends on \(module.dependencies.joined(separator: ", "))"
            let tests = module.tests.isEmpty ? "" : "; tested by \(module.tests.joined(separator: ", "))"
            lines.append("  \(module.name) (\(module.kind), \(module.project)): \(dependencies)\(tests)")
        }
        let counts = ModuleGraph.Placement.allCases.compactMap { placement in
            let count = graph.imports.count { $0.placement == placement }
            return count == 0 ? nil : "\(count) \(placement.rawValue)"
        }
        lines.append(counts.isEmpty ? "No source imports these modules." : "Imports of these modules: \(counts.joined(separator: ", ")).")
        for found in graph.imports where found.placement != .declared {
            lines.append("  \(found.placement.rawValue): \(found.target) imports \(found.module) at \(found.file):\(found.line)\(found.conditional == true ? ", inside #if" : "")")
        }
        if !graph.unimported.isEmpty {
            lines.append("Depended on, imported by no source of the target: " + graph.unimported.map { "\($0.target) on \($0.dependency)" }.joined(separator: ", ") + ".")
        }
        lines += graph.notes.map { "Not read: \($0)." }
        return lines
    }
}
