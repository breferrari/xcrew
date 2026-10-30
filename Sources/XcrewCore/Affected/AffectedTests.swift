import Foundation

/// The test targets a change can break: those of the targets that own the changed files, and of every target that
/// depends on those, at any depth, as the project declares them. A false "skip this" lets broken code look green, so
/// whatever the reading doesn't model runs everything, with the reason (docs/findings.md, *Affected tests*).
public struct AffectedTests: Sendable, Equatable, Codable {
    /// The test targets to run, for `-only-testing:`; nothing when everything must run.
    public var selections: [String]?
    /// Why everything must run, naming the file or project behind it.
    public var runAll: String?
    /// The selections that are UI test bundles; absent when none is.
    public var uiSelections: [String]?
    /// The shared schemes that test only targets in `selections`; absent when there are none.
    public var schemes: [TestSchemes.Scheme]?

    /// Files whose effect on the build the reading doesn't model: build settings, packages, test plans.
    static let everythingNames = Set(ProjectLayout.packageMarkers + ["Package.resolved"])
    static let everythingExtensions: Set = ["xcconfig", "xctestplan", "xcscheme"]

    /// `changed` holds paths from the project's root.
    public static func of(changed: [String], in project: Project) -> AffectedTests {
        if changed.isEmpty { return AffectedTests(selections: []) }
        let layout = project.layout(.anywhereButHome)
        let rootPath = ProjectLayout.canonical(project.root)
        let fromRoot = { (path: String) in path.hasPrefix(rootPath + "/") ? String(path.dropFirst(rootPath.count + 1)) : path }
        var graphs: [ProjectGraph] = []
        let containers = layout.containers.map { project.root.appending(path: $0) }
        for bundle in projects(in: containers) {
            do {
                let graph = try ProjectGraph.read(bundle)
                if let unmodeled = graph.unmodeled { return everything("\(fromRoot(ProjectLayout.canonical(bundle))): \(unmodeled)") }
                graphs.append(graph)
            } catch {
                return everything("\(fromRoot(ProjectLayout.canonical(bundle))) couldn't be read: \(error)")
            }
        }
        if graphs.isEmpty { return everything("no Xcode project was found to read") }
        let nearest = layout.generator
        var owners = Set<String>()
        for file in changed {
            let url = file.hasPrefix("/") ? URL(fileURLWithPath: file) : project.root.appending(path: file)
            let components = url.pathComponents
            if components.contains(where: Project.isXcodeContainer) { return everything("\(file) is part of a project or workspace") }
            if everythingNames.contains(url.lastPathComponent) || everythingExtensions.contains(url.pathExtension) { return everything("\(file) changes what the build does in a way this doesn't read") }
            if let nearest, layout.command(after: url, nearest: nearest) != nil { return everything("\(file) is a manifest the generator reads") }
            let path = ProjectLayout.canonicalCreating(url)
            var found = Set<String>()
            for graph in graphs {
                let owned = graph.owners(of: path)
                if owned.isExcepted { return everything("\(file) has a target membership of its own, which this doesn't read") }
                found.formUnion(owned.targets)
            }
            if found.isEmpty { return everything("no target owns \(file)") }
            owners.formUnion(found)
        }
        // Targets of the same name in two projects keep every dependency: dropping one could skip a test.
        var targets = graphs.reduce(into: [String: ProjectGraph.Target]()) { all, graph in
            all.merge(graph.targets) { first, second in ProjectGraph.Target(name: first.name, isTest: first.isTest || second.isTest, isUITest: first.isUITest || second.isUITest, dependencies: first.dependencies.union(second.dependencies)) }
        }
        // A module links the one below it by its product, and depends on another project's target by name: each
        // resolves among every project the workspace reads, and one that doesn't depends on something unread.
        let products = graphs.reduce(into: [String: String]()) { all, graph in all.merge(graph.products) { first, _ in first } }
        for graph in graphs {
            for (target, linked) in graph.links.sorted(by: { $0.key < $1.key }) {
                for product in linked.sorted() {
                    guard let producer = products[product] else { return everything("\(target) links \(product), which no project here builds") }
                    if producer != target { targets[target]?.dependencies.insert(producer) }
                }
            }
            for (target, names) in graph.external.sorted(by: { $0.key < $1.key }) {
                for name in names.sorted() {
                    guard targets[name] != nil else { return everything("\(target) depends on \(name), which no project here builds") }
                    targets[target]?.dependencies.insert(name)
                }
            }
        }
        // Every target that builds on an affected one is affected too, however far up.
        var affected = owners
        var grew = true
        while grew {
            grew = false
            for target in targets.values where !affected.contains(target.name) && !target.dependencies.isDisjoint(with: affected) {
                affected.insert(target.name)
                grew = true
            }
        }
        let selections = affected.filter { targets[$0]?.isTest == true }.sorted()
        let ui = selections.filter { targets[$0]?.isUITest == true }
        let schemes = TestSchemes.testingOnly(Set(selections), in: containers, from: project.root)
        return AffectedTests(selections: selections, runAll: nil, uiSelections: ui.isEmpty ? nil : ui, schemes: schemes.isEmpty ? nil : schemes)
    }

    static func everything(_ reason: String) -> AffectedTests {
        AffectedTests(selections: nil, runAll: reason)
    }

    /// The `.xcodeproj` bundles to read: the nearest project, or each one the nearest workspace refers to.
    static func projects(in containers: [URL]) -> [URL] {
        let workspaces = containers.filter { Project.isXcodeWorkspace($0.lastPathComponent) }
        let referenced = workspaces.flatMap(TestSchemes.projects)
        let bundles = referenced + containers.filter { Project.isXcodeProject($0.lastPathComponent) }
        return bundles.reduce(into: []) { unique, bundle in if !unique.contains(where: { ProjectLayout.canonical($0) == ProjectLayout.canonical(bundle) }) { unique.append(bundle) } }
    }
}
