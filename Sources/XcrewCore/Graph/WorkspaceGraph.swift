import Foundation

/// Every Xcode project a project's nearest workspace refers to, read, with each target's dependencies resolved across
/// them: a module links the one below it by its product, and depends on another project's target by name. What
/// `affected` and `graph` both read; a project it can't read, or a dependency nothing here builds, is a reason instead.
struct WorkspaceGraph: Sendable {
    /// The project's root, canonical, which paths are given from.
    let root: String
    /// The project's nearest Xcode containers, as its layout finds them.
    let containers: [URL]
    /// Each `.xcodeproj` bundle read, with its canonical path and what it says.
    var projects: [(bundle: String, graph: ProjectGraph)]
    /// Every target of every project, by name, with each target it builds on resolved across the projects, and how.
    var targets: [String: ProjectGraph.Target]

    /// Why the workspace couldn't be read whole, naming the file or target behind it.
    struct Unread: Error, Equatable {
        let reason: String
    }

    static func read(_ project: Project) -> Result<WorkspaceGraph, Unread> {
        let layout = project.layout(.anywhereButHome)
        let root = ProjectLayout.canonical(project.root)
        let containers = layout.containers.map { project.root.appending(path: $0) }
        var projects: [(bundle: String, graph: ProjectGraph)] = []
        for bundle in bundles(in: containers) {
            let path = ProjectLayout.canonical(bundle)
            do {
                let graph = try ProjectGraph.read(bundle)
                if let unmodeled = graph.unmodeled { return .failure(Unread(reason: "\(ProjectLayout.path(path, from: root)): \(unmodeled)")) }
                projects.append((path, graph))
            } catch {
                return .failure(Unread(reason: "\(ProjectLayout.path(path, from: root)) couldn't be read: \(error)"))
            }
        }
        if projects.isEmpty { return .failure(Unread(reason: "no Xcode project was found to read")) }
        // Targets of the same name in two projects keep every edge: dropping one could skip a test.
        var targets = projects.reduce(into: [String: ProjectGraph.Target]()) { all, project in
            all.merge(project.graph.targets) { $0.merged(with: $1) }
        }
        let products = projects.reduce(into: [String: String]()) { all, project in all.merge(project.graph.products) { first, _ in first } }
        for (_, graph) in projects {
            for (target, built) in graph.productEdges.sorted(by: { $0.key < $1.key }) {
                for (product, edges) in built.sorted(by: { $0.key < $1.key }) {
                    guard let producer = products[product] else { return .failure(Unread(reason: "\(target) builds on \(product), which no project here builds")) }
                    if producer != target { for edge in edges { targets[target]?.add(producer, as: edge) } }
                }
            }
            for (target, names) in graph.external.sorted(by: { $0.key < $1.key }) {
                for name in names.sorted() {
                    guard targets[name] != nil else { return .failure(Unread(reason: "\(target) depends on \(name), which no project here builds")) }
                    targets[target]?.add(name, as: .named)
                }
            }
        }
        return .success(WorkspaceGraph(root: root, containers: containers, projects: projects, targets: targets))
    }

    /// The targets that own the file at a canonical path, across the projects, and whether an exception set changes its
    /// membership in any of them, which the reading doesn't model. With `compiledOnly`, a listed file counts for the
    /// targets that compile it alone.
    func owners(of path: String, compiledOnly: Bool = false) -> (targets: Set<String>, isExcepted: Bool) {
        projects.reduce(into: (targets: Set<String>(), isExcepted: false)) { all, project in
            let owned = project.graph.owners(of: path, compiledOnly: compiledOnly)
            all.targets.formUnion(owned.targets)
            all.isExcepted = all.isExcepted || owned.isExcepted
        }
    }

    /// The targets that build the file at a canonical path: for a Swift file, those that compile it, not one that only
    /// copies it as a resource; for any other, every target that lists it.
    func builders(of path: String) -> (targets: Set<String>, isExcepted: Bool) {
        owners(of: path, compiledOnly: path.hasSuffix(".swift"))
    }

    /// The `.xcodeproj` bundles to read: the nearest project, or each one the nearest workspace refers to.
    static func bundles(in containers: [URL]) -> [URL] {
        let workspaces = containers.filter { Project.isXcodeWorkspace($0.lastPathComponent) }
        let referenced = workspaces.flatMap(TestSchemes.projects)
        let bundles = referenced + containers.filter { Project.isXcodeProject($0.lastPathComponent) }
        return bundles.reduce(into: []) { unique, bundle in if !unique.contains(where: { ProjectLayout.canonical($0) == ProjectLayout.canonical(bundle) }) { unique.append(bundle) } }
    }
}
