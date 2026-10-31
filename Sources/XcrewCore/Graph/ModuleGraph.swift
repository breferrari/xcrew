import Foundation

/// A workspace's modules as its projects declare them, and where each source's imports of those modules land in that
/// graph. The declared dependencies are the layers: no other file of a project names them (docs/findings.md, *The
/// module graph*). Each import gets a class, stated as a fact, with no verdict.
public struct ModuleGraph: Sendable, Equatable, Codable {
    public struct Module: Sendable, Equatable, Codable {
        /// The name a source imports it by.
        public let name: String
        public let target: String
        /// The product type, as the project file writes it after `com.apple.product-type.`: `framework`, `application`.
        public let kind: String
        /// The project file's path from the root.
        public let project: String
        /// The targets it depends on directly, resolved across the workspace's projects.
        public let dependencies: [String]
        /// The test targets that depend on it directly.
        public let tests: [String]
        /// Frameworks it embeds without linking or naming them as dependencies; absent when none.
        public var embeds: [String]?
    }

    /// Where an imported module sits relative to the target that imports it.
    public enum Placement: String, Sendable, Codable, CaseIterable {
        /// A direct dependency.
        case declared
        /// Reachable through other dependencies, not a direct one.
        case transitiveOnly = "transitive-only"
        /// Neither a dependency nor reachable through one.
        case undeclared
        /// It depends on the importer: the import points down the graph's other way.
        case upward
    }

    public struct Import: Sendable, Equatable, Codable {
        public let target: String
        /// The file's path from the root.
        public let file: String
        public let line: Int
        public let module: String
        public let placement: Placement
        /// Inside `#if`; absent when not.
        public var conditional: Bool?
    }

    /// A direct dependency on a framework or library that none of the target's sources imports.
    public struct Unimported: Sendable, Equatable, Codable {
        public let target: String
        public let dependency: String
    }

    public var modules: [Module] = []
    /// Each import of one of the workspace's modules.
    public var imports: [Import] = []
    /// Imports of modules no project here builds, the system's and packages', by module, with how many there are.
    public var otherImports: [String: Int] = [:]
    public var unimported: [Unimported] = []
    /// What the reading couldn't settle, the rest still said: a module name built from a setting, a file whose target
    /// an exception set changes.
    public var notes: [String] = []
    /// Why the workspace couldn't be read; nothing else is said then.
    public var unread: String?

    /// Whether a target's product is one a source imports by module name, a framework or a library of any linkage; an
    /// app or an extension is embedded or hosted, not imported.
    static func isImportable(_ kind: String) -> Bool {
        kind.hasPrefix("framework") || kind.hasPrefix("library")
    }

    public static func read(_ project: Project) -> ModuleGraph {
        let workspace: WorkspaceGraph
        switch WorkspaceGraph.read(project) {
        case let .success(read): workspace = read
        case let .failure(unread): return ModuleGraph(unread: unread.reason)
        }
        let fromRoot = { (path: String) in ProjectLayout.path(path, from: workspace.root) }
        var graph = ModuleGraph()
        var projectOf: [String: String] = [:]
        var productFiles: [String: String] = [:]
        var settings: [String: ProjectGraph.Setting] = [:]
        for (bundle, read) in workspace.projects {
            for name in read.targets.keys where projectOf[name] == nil { projectOf[name] = fromRoot(bundle) }
            productFiles.merge(read.productFiles) { first, _ in first }
            settings.merge(read.settings[ProjectGraph.moduleName] ?? [:]) { $0.merged(with: $1) }
        }
        let targets = workspace.targets
        let declared = targets.mapValues(\.declared)
        var moduleNames: [String: String] = [:]
        for target in targets.keys.sorted() {
            let fallback = identifier(productFiles[target].map(productName) ?? target)
            let setting = settings[target] ?? ProjectGraph.Setting()
            let set = setting.values.sorted()
            if let literal = setting.literal {
                moduleNames[target] = literal
            } else {
                moduleNames[target] = fallback
                if set.contains(where: { $0.contains("$") }) {
                    graph.notes.append("\(target)'s module name is set from another setting (\(set.joined(separator: ", "))), so imports of it are read under \(fallback)")
                } else if setting.isPartial {
                    graph.notes.append("\(target)'s module name is set for some configurations only (\(set.joined(separator: ", "))), so imports of it are read under \(fallback)")
                } else if set.count > 1 {
                    graph.notes.append("\(target)'s module name differs between configurations (\(set.joined(separator: ", "))), so imports of it are read under \(fallback)")
                }
            }
        }
        // A target with no product type, an aggregate, builds no module.
        let moduleTargets = targets.values.filter { !$0.isTest && !$0.kind.isEmpty }
        // Two targets can build one module name, one per platform: an import is placed by the one nearest the importer.
        let byModule = Dictionary(grouping: moduleTargets.map(\.name).sorted()) { moduleNames[$0, default: $0] }
        var reached: [String: Set<String>] = [:]
        func reachable(from target: String) -> Set<String> {
            if let known = reached[target] { return known }
            var found = Set<String>()
            var next = Array(declared[target] ?? [])
            while let name = next.popLast() {
                guard found.insert(name).inserted else { continue }
                next.append(contentsOf: declared[name] ?? [])
            }
            reached[target] = found
            return found
        }
        let testers = targets.values.filter(\.isTest).reduce(into: [String: [String]]()) { all, test in
            for dependency in declared[test.name] ?? [] { all[dependency, default: []].append(test.name) }
        }
        graph.modules = moduleTargets.map { target in
            Module(
                name: moduleNames[target.name, default: target.name], target: target.name, kind: target.kind, project: projectOf[target.name] ?? "",
                dependencies: (declared[target.name] ?? []).sorted(), tests: testers[target.name, default: []].sorted(),
                embeds: target.embedded.isEmpty ? nil : target.embedded.sorted()
            )
        }.sorted { ($0.name, $0.target) < ($1.name, $1.target) }
        var imported: [String: Set<String>] = [:]
        let (sources, excepted) = sources(of: workspace)
        graph.notes += excepted.sorted().map { "\(fromRoot($0)) has a target membership of its own, which this doesn't read" }
        for (file, owners) in sources.sorted(by: { $0.key < $1.key }) {
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            let owners = owners.sorted()
            for found in SwiftImport.all(in: text) {
                guard let candidates = byModule[found.module] else {
                    graph.otherImports[found.module, default: 0] += 1
                    continue
                }
                for owner in owners where !candidates.contains(owner) {
                    func placement(of target: String) -> Placement {
                        if declared[owner]?.contains(target) == true { .declared }
                        else if reachable(from: owner).contains(target) { .transitiveOnly }
                        else if reachable(from: target).contains(owner) { .upward }
                        else { .undeclared }
                    }
                    let placed = candidates.map { ($0, placement(of: $0)) }
                    guard let (importedTarget, placement) = Placement.allCases.lazy.compactMap({ wanted in placed.first { $0.1 == wanted } }).first else { continue }
                    imported[owner, default: []].insert(importedTarget)
                    graph.imports.append(Import(target: owner, file: fromRoot(file), line: found.line, module: found.module, placement: placement, conditional: found.isConditional ? true : nil))
                }
            }
        }
        graph.imports.sort { ($0.target, $0.file, $0.line) < ($1.target, $1.file, $1.line) }
        graph.unimported = targets.values.flatMap { target in
            (declared[target.name] ?? []).filter { isImportable(targets[$0]?.kind ?? "") && !(imported[target.name]?.contains($0) ?? false) }.map { Unimported(target: target.name, dependency: $0) }
        }.sorted { ($0.target, $0.dependency) < ($1.target, $1.dependency) }
        return graph
    }

    /// Each Swift file a target of the workspace builds, by canonical path, with the targets that own it: the files the
    /// projects list, and those under each folder they list whole. A file whose membership an exception set changes is
    /// left out, as `affected` can't say whose it is either, and returned apart.
    static func sources(of workspace: WorkspaceGraph) -> (owned: [String: Set<String>], excepted: Set<String>) {
        var files: [String: Set<String>] = [:]
        var excepted = Set<String>()
        // A path is looked up in the project that lists it, not in every project of the workspace.
        for (_, graph) in workspace.projects {
            var paths = Set(graph.compiled.keys.filter { $0.hasSuffix(".swift") })
            for folder in graph.folders {
                let base = URL(fileURLWithPath: folder.path)
                let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
                while let url = enumerator?.nextObject() as? URL {
                    if url.pathExtension == "swift" { paths.insert(folder.path + "/" + url.path.dropFirst(base.path.count + 1)) }
                }
            }
            for path in paths {
                let owned = graph.owners(of: path, compiledOnly: true)
                if owned.isExcepted { excepted.insert(path) } else if !owned.targets.isEmpty { files[path, default: []].formUnion(owned.targets) }
            }
        }
        return (files, excepted)
    }

    /// A product's name, from its file's: `Core` for `Core.framework`, and for a library's `libCore.a` too.
    static func productName(_ file: String) -> String {
        let name = (file as NSString).deletingPathExtension
        return ["a", "dylib"].contains((file as NSString).pathExtension) && name.hasPrefix("lib") ? String(name.dropFirst(3)) : name
    }

    /// A name as Xcode makes a module name of it when nothing sets one: each character that's no letter, digit or `_`
    /// becomes `_`, and so does a leading digit (`My-Kit 2` is `My_Kit_2`, `2Fast` is `_Fast`; docs/findings.md).
    static func identifier(_ name: String) -> String {
        String(name.enumerated().map { index, character in
            character == "_" || character.isLetter || (character.isNumber && index > 0) ? character : "_"
        })
    }
}
