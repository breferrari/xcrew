import Foundation

/// What a project file says about which target owns each file and which targets depend on which: the facts affected
/// tests need, in either format, `project.pbxproj` or Xcode 27.2's `project.xcproj` (docs/findings.md, *Affected
/// tests*). Whatever the reading meets and doesn't model is kept as a reason, which runs everything.
struct ProjectGraph: Sendable {
    struct Target: Sendable, Equatable {
        let name: String
        let isTest: Bool
        /// The targets it builds on: its dependencies and, for a test bundle, the app it runs in.
        var dependencies: Set<String>
    }

    /// A folder whose files all join `targets`, but for the files an exception set names, whose membership differs.
    struct Folder: Sendable {
        let path: String
        let targets: Set<String>
        let excepted: Set<String>
    }

    var targets: [String: Target] = [:]
    /// Each file a target lists, by canonical path.
    var owners: [String: Set<String>] = [:]
    var folders: [Folder] = []
    /// Something the reading didn't model: the selection can't be trusted.
    var unmodeled: String?

    /// The targets that own the file at a canonical path, or nothing when the project names none; `excepted` when an
    /// exception set changes its membership, itself or a folder above it, which the reading doesn't model. A file inside
    /// a bundle the project lists whole, an asset catalog or a data model, is the bundle's.
    func owners(of path: String) -> (targets: Set<String>, isExcepted: Bool) {
        var found = Set<String>()
        var ancestor = path
        while !ancestor.isEmpty {
            found.formUnion(owners[ancestor] ?? [])
            ancestor = (ancestor as NSString).deletingLastPathComponent
            if ancestor == "/" { break }
        }
        var isExcepted = false
        for folder in folders where path.hasPrefix(folder.path + "/") {
            if folder.excepted.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { isExcepted = true } else { found.formUnion(folder.targets) }
        }
        return (found, isExcepted)
    }

    /// Reads the project file of an `.xcodeproj` bundle.
    static func read(_ bundle: URL) throws -> ProjectGraph {
        guard let file = ProjectLayout.projectFile(in: bundle) else { throw ReadError(reason: "no project file") }
        let data = try Data(contentsOf: file)
        return file.lastPathComponent == ProjectLayout.jsonProject ? try json(data, in: bundle.deletingLastPathComponent()) : try pbxproj(data, in: bundle.deletingLastPathComponent())
    }

    struct ReadError: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }

    // MARK: project.pbxproj

    static func pbxproj(_ data: Data, in folder: URL) throws -> ProjectGraph {
        guard let plist = try PropertyListDecoder().decode(PlistValue.self, from: data).foundation as? [String: Any],
              let objects = plist["objects"] as? [String: [String: Any]] else { throw ReadError(reason: "not a property list of objects") }
        var parents: [String: String] = [:]
        for (id, object) in objects {
            for child in object["children"] as? [String] ?? [] { parents[child] = id }
        }
        // Paths join onto the folder as the file system spells it, once, rather than asking the file system per file.
        let projectFolder = URL(fileURLWithPath: ProjectLayout.canonical(folder))
        var located: [String: URL?] = [:]
        func location(_ id: String) -> URL? {
            if let known = located[id] { return known }
            let found = resolve(id)
            located[id] = found
            return found
        }
        func resolve(_ id: String) -> URL? {
            guard let object = objects[id] else { return nil }
            let path = object["path"] as? String
            switch object["sourceTree"] as? String {
            case "<group>":
                let base = parents[id].flatMap(location) ?? projectFolder
                return path.map { base.appending(path: $0) } ?? base
            case "SOURCE_ROOT": return path.map { projectFolder.appending(path: $0) } ?? projectFolder
            case "<absolute>": return path.map { URL(fileURLWithPath: $0) }
            default: return nil
            }
        }
        var graph = ProjectGraph()
        let natives = objects.filter { ["PBXNativeTarget", "PBXAggregateTarget"].contains($0.value["isa"] as? String) }
        let names = natives.compactMapValues { $0["name"] as? String }
        var productOwners: [String: String] = [:]
        for (id, target) in natives {
            guard let name = names[id] else { continue }
            if let product = (target["productReference"] as? String).flatMap({ objects[$0]?["path"] as? String }) { productOwners[(product as NSString).lastPathComponent] = name }
        }
        for (id, target) in natives {
            guard let name = names[id] else { continue }
            var dependencies = Set<String>()
            for dependency in target["dependencies"] as? [String] ?? [] {
                guard let targetID = objects[dependency]?["target"] as? String, let dependedOn = names[targetID] else {
                    graph.unmodeled = "\(name) depends on a target outside this project"
                    continue
                }
                dependencies.insert(dependedOn)
            }
            // A test bundle runs in its host app, named by the product its TEST_HOST setting points at.
            for host in testHosts(of: target, in: objects) {
                guard let hostTarget = productOwners[host] else { graph.unmodeled = "\(name) runs in \(host), which no target here builds"; continue }
                dependencies.insert(hostTarget)
            }
            for phase in target["buildPhases"] as? [String] ?? [] {
                for buildFile in objects[phase]?["files"] as? [String] ?? [] {
                    guard let reference = objects[buildFile]?["fileRef"] as? String else { continue }
                    let files = (objects[reference]?["isa"] as? String) == "PBXVariantGroup" ? (objects[reference]?["children"] as? [String] ?? []) : [reference]
                    for file in files {
                        // Linking another target's product depends on it, entry or not: Xcode finds it implicitly.
                        if objects[file]?["sourceTree"] as? String == "BUILT_PRODUCTS_DIR", let product = objects[file]?["path"] as? String {
                            if let producer = productOwners[(product as NSString).lastPathComponent], producer != name { dependencies.insert(producer) }
                            continue
                        }
                        guard let url = location(file) else { continue }
                        graph.owners[Self.lexical(url), default: []].insert(name)
                    }
                }
            }
            let productType = target["productType"] as? String ?? ""
            graph.targets[name] = Target(name: name, isTest: productType.contains("test"), dependencies: dependencies)
            for group in target["fileSystemSynchronizedGroups"] as? [String] ?? [] {
                guard let url = location(group) else { graph.unmodeled = "a folder of \(name) isn't in the project folder"; continue }
                let excepted = (objects[group]?["exceptions"] as? [String] ?? []).flatMap { objects[$0]?["membershipExceptions"] as? [String] ?? [] }
                graph.addFolder(Self.lexical(url), targets: [name], excepted: excepted)
            }
        }
        return graph
    }

    /// The app products a target's `TEST_HOST` names, across its configurations: `App.app` for `$(BUILT_PRODUCTS_DIR)/App.app/…`.
    static func testHosts(of target: [String: Any], in objects: [String: [String: Any]]) -> Set<String> {
        let configurations = (target["buildConfigurationList"] as? String).flatMap { objects[$0]?["buildConfigurations"] as? [String] } ?? []
        return Set(configurations.compactMap { (objects[$0]?["buildSettings"] as? [String: Any])?["TEST_HOST"] as? String }.compactMap(hostProduct))
    }

    static func hostProduct(_ testHost: String) -> String? {
        testHost.split(separator: "/").first { $0.hasSuffix(".app") }.map(String.init)
    }

    /// A path with `.` and `..` resolved by its words alone. `standardizedFileURL` would also drop `/private` from
    /// `/private/var`, while the paths it's matched against keep it.
    static func lexical(_ url: URL) -> String {
        var parts: [String] = []
        for part in url.path.split(separator: "/") {
            switch part {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(String(part))
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    mutating func addFolder(_ path: String, targets: Set<String>, excepted: [String]) {
        let exceptedPaths = Set(excepted.map { Self.lexical(URL(fileURLWithPath: path).appending(path: $0)) })
        if let index = folders.firstIndex(where: { $0.path == path }) {
            folders[index] = Folder(path: path, targets: folders[index].targets.union(targets), excepted: folders[index].excepted.union(exceptedPaths))
        } else {
            folders.append(Folder(path: path, targets: targets, excepted: exceptedPaths))
        }
    }

    // MARK: project.xcproj

    /// Xcode 27.2's JSON format, by the keys of Apple's `xcode-project-format` schema. It allows trailing commas.
    static func json(_ data: Data, in folder: URL) throws -> ProjectGraph {
        guard let project = try JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) as? [String: Any] else { throw ReadError(reason: "not a JSON object") }
        var graph = ProjectGraph()
        let targets = project["targets"] as? [[String: Any]] ?? []
        let namesByID = Dictionary(targets.compactMap { target in (target["id"] as? String).flatMap { id in (target["name"] as? String).map { (id, $0) } } }, uniquingKeysWith: { first, _ in first })
        let names = Set(targets.compactMap { $0["name"] as? String })
        let producers = Dictionary(targets.compactMap { target in (target["product"] as? String).flatMap { product in (target["name"] as? String).map { ((product as NSString).lastPathComponent, $0) } } }, uniquingKeysWith: { first, _ in first })
        func targetName(_ reference: Any) -> String? {
            guard let text = reference as? String ?? (reference as? [String: Any]).flatMap({ $0["build-phase"] as? String ?? $0["target"] as? String }) else { return nil }
            let name = String(text.split(separator: "/").first ?? "")
            return names.contains(name) ? name : namesByID[name]
        }
        for target in targets {
            guard let name = target["name"] as? String else { continue }
            var dependencies = Set<String>()
            for reference in (target["dependencies"] as? [Any] ?? []) + [target["test-host-target"]].compactMap({ $0 }) {
                guard let dependedOn = targetName(reference) else { graph.unmodeled = "\(name) depends on a target outside this project"; continue }
                dependencies.insert(dependedOn)
            }
            graph.targets[name] = Target(name: name, isTest: (target["product-type"] as? String ?? "").contains("test"), dependencies: dependencies)
        }
        func walk(_ nodes: [[String: Any]], in base: URL) {
            for node in nodes {
                let path = node["path"] as? String
                // A path from another base, `<PRODUCTS>/App.app`, is no file of the project's; a target it's a member of links it,
                // and so depends on the target that builds it, entry or not.
                if let path, path.hasPrefix("<") {
                    let product = (path as NSString).lastPathComponent
                    for member in (node["target-membership"] as? [Any] ?? []).compactMap(targetName) {
                        if let producer = producers[product], producer != member { graph.targets[member]?.dependencies.insert(producer) }
                    }
                    continue
                }
                let url = path.map { base.appending(path: $0) } ?? base
                let membership = (node["target-membership"] as? [Any] ?? []).compactMap(targetName)
                if (node["target-membership"] as? [Any] ?? []).count != membership.count { graph.unmodeled = "\(path ?? "a file") joins a target the reading can't resolve" }
                switch node["kind"] as? String {
                case "folder":
                    let excepted = (node["membership-exceptions"] as? [[String: Any]] ?? []).flatMap { ($0["inclusions"] as? [String] ?? []) + ($0["exclusions"] as? [String] ?? []) }
                    graph.addFolder(Self.lexical(url), targets: Set(membership), excepted: excepted)
                case "group", "variant-group", "version-group":
                    walk(node["children"] as? [[String: Any]] ?? [], in: url)
                default:
                    for target in membership { graph.owners[Self.lexical(url), default: []].insert(target) }
                }
            }
        }
        walk(project["files"] as? [[String: Any]] ?? [], in: URL(fileURLWithPath: ProjectLayout.canonical(folder)))
        return graph
    }
}
