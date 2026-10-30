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
        let schemes = TestSchemes.testingOnly(Set(selections), in: workspace.containers, from: project.root)
        return AffectedTests(selections: selections, runAll: nil, uiSelections: ui.isEmpty ? nil : ui, schemes: schemes.isEmpty ? nil : schemes)
    }

    static func everything(_ reason: String) -> AffectedTests {
        AffectedTests(selections: nil, runAll: reason)
    }
}
