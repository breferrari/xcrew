import Foundation

/// A build's Swift concurrency diagnostics, from its log, by the compiler's own group and by module: facts, each
/// diagnostic once however often the log repeats it.
public struct ConcurrencyReport: Sendable, Equatable, Codable {
    public struct Group: Sendable, Equatable, Codable {
        /// The group as the compiler names it; a group under another goes by its own name.
        public let name: String
        /// Its doc's title, when the docs were read.
        public var title: String?
        public let count: Int
        /// How many are in each module.
        public let modules: [String: Int]
    }

    public struct Module: Sendable, Equatable, Codable {
        public let name: String
        public let count: Int
    }

    /// The concurrency diagnostics, each once.
    public var count = 0
    /// How many of them are errors.
    public var errors = 0
    /// The groups, most first.
    public var groups: [Group] = []
    /// The modules, most first.
    public var modules: [Module] = []
    /// Diagnostics the log holds with no group: not counted, since only the text would say what they're about.
    public var ungrouped = 0
    /// How many are in lines the branch changed; absent when git couldn't say.
    public var inChangedLines: Int?
    /// Whether the groups came from the toolchain's docs rather than their names.
    public var groupsFromDocs = false

    /// The module a diagnostic's file is in when no project here builds it.
    public static let noModule = "not in a project"

    /// The log's concurrency diagnostics, the modules from the project's targets. `changed` limits them to lines the
    /// branch changed, when given.
    public static func read(log: URL, project: Project, groups: ConcurrencyGroups, onlyChanged: Bool = false, using runner: any CommandRunning) async throws -> ConcurrencyReport {
        var found = Set<CompilerDiagnostic>()
        var ungrouped = Set<CompilerDiagnostic>()
        try LogLines.forEach(in: log) { line in
            guard let diagnostic = CompilerDiagnostic.parse(line) else { return }
            if diagnostic.groups.isEmpty { ungrouped.insert(diagnostic) } else if groups.counts(diagnostic.groups) { found.insert(diagnostic) }
        }
        var report = ConcurrencyReport(ungrouped: ungrouped.count, groupsFromDocs: groups.isFromDocs)
        if case let .success(change) = await GitChanges.since(nil, in: project, using: runner),
           let changed = await ChangedLines.of(found.map(\.path), in: change, project: project, using: runner) {
            let inChanged = found.filter { diagnostic in changed[diagnostic.path]?.contains { $0.contains(diagnostic.line) } == true }
            report.inChangedLines = inChanged.count
            if onlyChanged { found = inChanged }
        }
        let workspace = try? WorkspaceGraph.read(project).get()
        let modules = Dictionary(Set(found.map(\.path)).map { path in
            (path, workspace?.owners(of: path).targets.sorted().first ?? noModule)
        }, uniquingKeysWith: { first, _ in first })
        let byGroup = Dictionary(grouping: found) { $0.groups.last ?? "" }
        report.count = found.count
        report.errors = found.filter(\.isError).count
        report.groups = byGroup.map { name, diagnostics in
            Group(name: name, title: groups.titles[name], count: diagnostics.count, modules: Dictionary(grouping: diagnostics) { modules[$0.path] ?? noModule }.mapValues(\.count))
        }.sorted { ($1.count, $0.name) < ($0.count, $1.name) }
        report.modules = Dictionary(grouping: found) { modules[$0.path] ?? noModule }
            .map { Module(name: $0.key, count: $0.value.count) }
            .sorted { ($1.count, $0.name) < ($0.count, $1.name) }
        return report
    }
}
