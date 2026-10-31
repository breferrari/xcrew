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
        /// How many are in each module, most first.
        public let modules: [Module]
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
    /// Why the branch's changed lines couldn't be read; absent when they could, or weren't asked for.
    public var changeUnread: String?
    /// The Xcode the log names, whose docs said which groups are about concurrency.
    public var xcode: String?
    /// Why the project couldn't be read, so modules come from the log's task headers alone.
    public var projectUnread: String?

    /// How many concurrency diagnostics a build's log holds before the note after it gives them.
    public static let noteAt = 10

    /// The note after a build with `noteAt` or more: the counts, as facts, and the command that lists them.
    public var summary: ConcurrencySummary? {
        guard count >= Self.noteAt else { return nil }
        let note = "xcrew: this build's log has \(Space.counted(count, "Swift concurrency diagnostic")) in \(Space.counted(modules.count, "module")); `xcrew concurrency` lists them by compiler group and module."
        return ConcurrencySummary(count: count, note: note)
    }

    /// The module a diagnostic's file is in when no project here builds it.
    public static let noModule = "not in a project"

    /// The log's concurrency diagnostics, the modules from the project's targets. `changed` limits them to lines the
    /// branch changed, when given.
    /// The log's report, its groups from the docs of the Xcode it names, else the one builds use on `machine`, looked up
    /// only then. `readsChanges` false leaves git alone: the note after a build gives no changed-line count.
    public static func read(log: URL, project: Project, machine: Machine, onlyChanged: Bool = false, readsChanges: Bool = true) async throws -> ConcurrencyReport {
        try await read(log: log, project: project, groups: { named in
            let xcode = if let named { named } else { await Xcodes.selected(on: machine).map { URL(fileURLWithPath: $0.path) } }
            return .read(docs: xcode.map(ConcurrencyGroups.docs(in:)))
        }, onlyChanged: onlyChanged, readsChanges: readsChanges, using: machine.runner)
    }

    public static func read(log: URL, project: Project, groups docs: @Sendable (URL?) async -> ConcurrencyGroups, onlyChanged: Bool = false, readsChanges: Bool = true, using runner: any CommandRunning) async throws -> ConcurrencyReport {
        var listed: [(diagnostic: CompilerDiagnostic, target: String?)] = []
        var target: String?
        var xcode: URL?
        try LogLines.forEach(in: log) { line in
            // A task's header, `SwiftCompile … (in target 'Kit' from project 'App')`, names the target its diagnostics
            // below are in; a diagnostic's line begins with its path.
            let bytes = line.utf8
            if let first = bytes.first, first != UInt8(ascii: "/"), first != UInt8(ascii: " "),
               let start = CompilerDiagnostic.end(of: targetBytes, in: bytes), let close = bytes[start...].firstIndex(of: UInt8(ascii: "'")) {
                target = String(Substring(bytes[start..<close]))
                return
            }
            // The Xcode that built it, from the first path into its developer folder.
            if xcode == nil, let end = CompilerDiagnostic.end(of: developerBytes, in: bytes) {
                let before = bytes[..<bytes.index(end, offsetBy: -"/Contents/Developer".utf8.count)]
                let start = before.lastIndex { $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\"") }.map { before.index(after: $0) } ?? before.startIndex
                xcode = URL(fileURLWithPath: String(Substring(before[start...])))
            }
            if let diagnostic = CompilerDiagnostic.parse(line) { listed.append((diagnostic, target)) }
        }
        let groups = await docs(xcode)
        // One spelling per file, as the project is read: the compiler writes a path as it was given.
        var spellings: [String: String] = [:]
        func canonical(_ path: String) -> String {
            if let known = spellings[path] { return known }
            let spelled = ProjectLayout.canonicalCreating(URL(fileURLWithPath: path))
            spellings[path] = spelled
            return spelled
        }
        var found: [CompilerDiagnostic: String?] = [:]
        var ungrouped = Set<CompilerDiagnostic>()
        for (diagnostic, target) in listed {
            let spelled = CompilerDiagnostic(path: canonical(diagnostic.path), line: diagnostic.line, isError: diagnostic.isError, message: diagnostic.message, groups: diagnostic.groups)
            if spelled.groups.isEmpty {
                if spelled.path.hasSuffix(".swift") { ungrouped.insert(spelled) }
            } else if groups.counts(spelled.groups), found[spelled] == nil {
                found[spelled] = target
            }
        }
        var report = ConcurrencyReport(groupsFromDocs: groups.isFromDocs, xcode: xcode?.path)
        if readsChanges, !found.isEmpty || (onlyChanged && !ungrouped.isEmpty) {
            switch await GitChanges.since(nil, in: project, using: runner) {
            case let .failure(failure):
                if onlyChanged { report.changeUnread = failure.description }
            case let .success(change):
                if let changed = await ChangedLines.of(Set(found.keys.map(\.path)).union(ungrouped.map(\.path)), in: change, project: project, using: runner) {
                    let isChanged = { (diagnostic: CompilerDiagnostic) in ChangedLines.holds(changed, path: diagnostic.path, line: diagnostic.line) }
                    report.inChangedLines = found.keys.filter(isChanged).count
                    if onlyChanged {
                        found = found.filter { isChanged($0.key) }
                        ungrouped = ungrouped.filter(isChanged)
                    }
                } else if onlyChanged {
                    report.changeUnread = "git couldn't diff the change"
                }
            }
        }
        report.ungrouped = ungrouped.count
        var workspace: WorkspaceGraph?
        if found.values.contains(where: { $0 == nil }) {
            switch WorkspaceGraph.read(project) {
            case let .success(read): workspace = read
            case let .failure(unread): report.projectUnread = unread.reason
            }
        }
        let modules = found.mapValues { target in target }.reduce(into: [CompilerDiagnostic: String]()) { all, entry in
            all[entry.key] = entry.value ?? workspace?.owners(of: entry.key.path).targets.sorted().first ?? noModule
        }
        report.count = found.count
        report.errors = found.keys.filter(\.isError).count
        report.groups = Dictionary(grouping: found.keys) { $0.groups.last ?? "" }.map { name, diagnostics in
            Group(name: name, title: groups.titles[name], count: diagnostics.count, modules: counted(diagnostics.map { modules[$0] ?? noModule }))
        }.sorted { ($1.count, $0.name) < ($0.count, $1.name) }
        report.modules = counted(found.keys.map { modules[$0] ?? noModule })
        return report
    }

    /// Each module once with how many of `names` it is, most first.
    static func counted(_ names: [String]) -> [Module] {
        Dictionary(grouping: names) { $0 }.map { Module(name: $0.key, count: $0.value.count) }.sorted { ($1.count, $0.name) < ($0.count, $1.name) }
    }

    static let targetBytes = Array("(in target '".utf8), developerBytes = Array(".app/Contents/Developer".utf8)
}
