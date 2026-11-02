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
    /// The shared schemes that test only targets in `selections`; absent when there are none, or when `whole` is named.
    public var schemes: [TestSchemes.Scheme]?
    /// When the selections are most of the suite, the scheme that tests every one of them with the fewest targets beyond
    /// them: the one to run, and no other is named. Absent when no single scheme tests them all.
    public var whole: Reach?
    /// For the selected targets no scheme in `schemes` tests, the scheme that tests each with the fewest targets beyond
    /// the selections, each once; absent when every selected target is tested.
    public var nearest: [Reach]?

    /// A scheme that tests selected targets and maybe others: those it tests, and how many more.
    public struct Reach: Sendable, Equatable, Codable {
        public let name: String
        public let container: String
        public let tests: [String]
        public let more: Int
    }

    /// Files whose effect on the build the reading doesn't model: build settings, packages, test plans.
    static let everythingNames = Set(ProjectLayout.packageMarkers + ["Package.resolved"])
    static let everythingExtensions: Set = ["xcconfig", "xctestplan", "xcscheme"]

    /// `changed` holds paths from the project's root.
    public static func of(changed: [String], in project: Project) -> AffectedTests {
        if changed.isEmpty { return AffectedTests(selections: []) }
        let layout = project.layout(.anywhereButHome)
        let workspace: WorkspaceGraph
        switch WorkspaceGraph.read(project) {
        case let .success(read): workspace = read
        case let .failure(unread): return everything(unread.reason)
        }
        let nearest = layout.generator
        var owners = Set<String>()
        for file in changed {
            let url = file.hasPrefix("/") ? URL(fileURLWithPath: file) : project.root.appending(path: file)
            let components = url.pathComponents
            if components.contains(where: Project.isXcodeContainer) { return everything("\(file) is part of a project or workspace") }
            if everythingNames.contains(url.lastPathComponent) || everythingExtensions.contains(url.pathExtension) { return everything("\(file) changes what the build does in a way this doesn't read") }
            if let nearest, layout.command(after: url, nearest: nearest) != nil { return everything("\(file) is a manifest the generator reads") }
            let path = ProjectLayout.canonicalCreating(url)
            let (found, isExcepted) = workspace.owners(of: path)
            if isExcepted { return everything("\(file) has a target membership of its own, which this doesn't read") }
            if found.isEmpty { return everything("no target owns \(file)") }
            owners.formUnion(found)
        }
        let targets = workspace.targets
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
        let all = TestSchemes.testing(in: workspace.containers, from: project.root)
        let tests = targets.values.count { $0.isTest }
        let reach = Self.reach(of: all, selections: Set(selections), mostOf: tests)
        return AffectedTests(selections: selections, runAll: nil, uiSelections: ui.isEmpty ? nil : ui, schemes: reach.schemes.isEmpty ? nil : reach.schemes, whole: reach.whole, nearest: reach.nearest.isEmpty ? nil : reach.nearest)
    }

    /// What to name for a selection out of a suite of `tests` test targets: past half of them, the scheme that tests every
    /// selected target with the fewest beyond them, alone; else the schemes that test only selected targets, and for each
    /// selected target none of those tests, the scheme that tests it with the fewest beyond the selection.
    static func reach(of schemes: [TestSchemes.Scheme], selections: Set<String>, mostOf tests: Int) -> (schemes: [TestSchemes.Scheme], whole: Reach?, nearest: [Reach]) {
        func reach(_ scheme: TestSchemes.Scheme) -> Reach {
            Reach(name: scheme.name, container: scheme.container, tests: scheme.targets.filter(selections.contains), more: scheme.targets.count { !selections.contains($0) })
        }
        let fewestMore = { (lhs: Reach, rhs: Reach) in (lhs.more, lhs.name, lhs.container) < (rhs.more, rhs.name, rhs.container) }
        if selections.count * 2 > tests, let whole = schemes.map(reach).filter({ Set($0.tests) == selections }).min(by: fewestMore) {
            return ([], whole, [])
        }
        let only = schemes.filter { Set($0.targets).isSubset(of: selections) }
        let tested = Set(only.flatMap(\.targets))
        var nearest: [Reach] = []
        for target in selections.subtracting(tested).sorted() where !nearest.contains(where: { $0.tests.contains(target) }) {
            if let best = schemes.filter({ $0.targets.contains(target) }).map(reach).min(by: fewestMore) { nearest.append(best) }
        }
        return (only, nil, nearest)
    }

    static func everything(_ reason: String) -> AffectedTests {
        AffectedTests(selections: nil, runAll: reason)
    }
}
