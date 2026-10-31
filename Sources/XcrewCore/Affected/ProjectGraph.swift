import Foundation

/// What a project file says about which target owns each file and which targets depend on which: the facts affected
/// tests need, in either format, `project.pbxproj` or Xcode 27.2's `project.xcproj` (docs/findings.md, *Affected
/// tests*). Whatever the reading meets and doesn't model is kept as a reason, which runs everything.
struct ProjectGraph: Sendable {
    /// How a target comes to build on another: named as a dependency, linking its product, copying its product in without
    /// linking it, or running in it as a test bundle's host app.
    enum Edge: Sendable, Hashable {
        case named, linked, embedded, testHost
    }

    struct Target: Sendable, Equatable {
        let name: String
        let isTest: Bool
        /// A UI test bundle, `…bundle.ui-testing`: it drives the app on a simulator, unlike a unit test bundle.
        let isUITest: Bool
        /// The targets it builds on, each with how it does.
        var edges: [String: Set<Edge>]
        /// The product type without `com.apple.product-type.`, as both formats name it: `framework`, `application`.
        let kind: String

        init(name: String, isTest: Bool, isUITest: Bool, edges: [String: Set<Edge>], kind: String) {
            (self.name, self.isTest, self.isUITest, self.edges, self.kind) = (name, isTest, isUITest, edges, kind)
        }

        /// A target as a project file declares it: what kind it is comes from its product type, in either format.
        init(name: String, productType: String, edges: [String: Set<Edge>]) {
            let kind = productType.hasPrefix(Self.productTypePrefix) ? String(productType.dropFirst(Self.productTypePrefix.count)) : productType
            self.init(name: name, isTest: productType.contains("test"), isUITest: productType.contains("ui-testing"), edges: edges, kind: kind)
        }

        static let productTypePrefix = "com.apple.product-type."

        /// Every target it builds on, however: what `affected` follows, since a change to any of them reaches it.
        var dependencies: Set<String> { Set(edges.keys) }
        /// The targets it builds on other than by embedding alone: the layers `graph` reads, since embedding carries a
        /// binary, not a module.
        var declared: Set<String> { Set(edges.filter { $0.value != [.embedded] }.keys) }
        /// The targets it only embeds.
        var embedded: Set<String> { Set(edges.filter { $0.value == [.embedded] }.keys) }

        mutating func add(_ target: String, as edge: Edge) {
            edges[target, default: []].insert(edge)
        }

        /// This target and another of its name in another project, every edge of both kept: dropping one could skip a test.
        func merged(with other: Target) -> Target {
            Target(name: name, isTest: isTest || other.isTest, isUITest: isUITest || other.isUITest, edges: edges.merging(other.edges) { $0.union($1) }, kind: kind)
        }
    }

    /// A folder whose files all join `targets`, but for the files an exception set names, whose membership differs.
    struct Folder: Sendable {
        let path: String
        let targets: Set<String>
        let excepted: Set<String>
    }

    var targets: [String: Target] = [:]
    /// Each file a target lists, by canonical path, in any of its phases.
    var owners: [String: Set<String>] = [:]
    /// Of `owners`, the files a target compiles: those its Sources phase lists. The JSON reader doesn't read a member's
    /// phase yet, so there every file a target lists counts as one it compiles.
    var compiled: [String: Set<String>] = [:]
    var folders: [Folder] = []
    /// Each product a target here builds, by its file name: `Core.framework`.
    var products: [String: String] = [:]
    /// The products each target builds on, by their file names, each with how: linked, copied in (Tuist embeds every
    /// framework below an app's dependencies), or its test host; for the workspace to resolve across projects.
    var productEdges: [String: [String: Set<Edge>]] = [:]
    /// Targets in other projects a target depends on, by name, through a proxy into that project, for the workspace to
    /// resolve.
    var external: [String: Set<String>] = [:]
    /// What a target's own settings give one build setting, across its configurations.
    struct Setting: Sendable, Equatable {
        var values: Set<String> = []
        /// Set for some configurations only, the others left to what's around the target.
        var isPartial = false

        /// The value, when every configuration sets the same one and it names no other setting.
        var literal: String? {
            guard values.count == 1, !isPartial, let value = values.first, !value.contains("$") else { return nil }
            return value
        }

        func merged(with other: Setting) -> Setting {
            Setting(values: values.union(other.values), isPartial: isPartial || other.isPartial)
        }
    }

    /// The settings read from each target, the module graph's and setup's: by setting, then by target.
    static let moduleName = "PRODUCT_MODULE_NAME", bundleIdentifier = "PRODUCT_BUNDLE_IDENTIFIER"
    static let readSettings = [moduleName, bundleIdentifier]
    var settings: [String: [String: Setting]] = [:]
    /// Each target's product, by its file name: `Core.framework`.
    var productFiles: [String: String] = [:]
    /// Something the reading didn't model: the selection can't be trusted.
    var unmodeled: String?

    /// The targets that own the file at a canonical path, or nothing when the project names none; `excepted` when an
    /// exception set changes its membership, itself or a folder above it, which the reading doesn't model. A file inside
    /// a bundle the project lists whole, an asset catalog or a data model, is the bundle's. With `compiledOnly`, a file
    /// the project lists counts for the targets that compile it alone.
    func owners(of path: String, compiledOnly: Bool = false) -> (targets: Set<String>, isExcepted: Bool) {
        var found = Set<String>()
        var ancestor = path
        let listed = compiledOnly ? compiled : owners
        while !ancestor.isEmpty {
            found.formUnion(listed[ancestor] ?? [])
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
            if let product = (target["productReference"] as? String).flatMap({ objects[$0]?["path"] as? String }) {
                productOwners[(product as NSString).lastPathComponent] = name
                graph.productFiles[name] = (product as NSString).lastPathComponent
            }
        }
        graph.products = productOwners
        for (id, target) in natives {
            guard let name = names[id] else { continue }
            var edges: [String: Set<Edge>] = [:]
            for dependency in target["dependencies"] as? [String] ?? [] {
                if let targetID = objects[dependency]?["target"] as? String, let dependedOn = names[targetID] {
                    edges[dependedOn, default: []].insert(.named)
                } else if let proxy = (objects[dependency]?["targetProxy"] as? String).flatMap({ objects[$0] }),
                          let portal = (proxy["containerPortal"] as? String).flatMap({ objects[$0] }),
                          (portal["path"] as? String)?.hasSuffix(".xcodeproj") == true,
                          let remote = proxy["remoteInfo"] as? String {
                    // A proxy into another project's file: its target, by name, among the projects the workspace reads.
                    graph.external[name, default: []].insert(remote)
                } else {
                    graph.unmodeled = "\(name) depends on a target the reading can't resolve"
                }
            }
            // A test bundle runs in its host app, named by the product its TEST_HOST setting points at, built here or in
            // another project of the workspace.
            for host in testHosts(of: target, in: objects) { graph.productEdges[name, default: [:]][host, default: []].insert(.testHost) }
            for phase in target["buildPhases"] as? [String] ?? [] {
                let isa = objects[phase]?["isa"] as? String ?? ""
                let edge = Self.productPhases[isa]
                for buildFile in objects[phase]?["files"] as? [String] ?? [] {
                    guard let reference = objects[buildFile]?["fileRef"] as? String else { continue }
                    let files = (objects[reference]?["isa"] as? String) == "PBXVariantGroup" ? (objects[reference]?["children"] as? [String] ?? []) : [reference]
                    for file in files {
                        // Linking or embedding another target's product depends on it, entry or not: Xcode finds it implicitly.
                        // Anything else in the build folder, a file a script writes, is no product and no file of the project's.
                        if objects[file]?["sourceTree"] as? String == "BUILT_PRODUCTS_DIR", let product = objects[file]?["path"] as? String {
                            if let edge, Self.isProduct(product) {
                                graph.productEdges[name, default: [:]][(product as NSString).lastPathComponent, default: []].insert(edge)
                            }
                            continue
                        }
                        guard let url = location(file) else { continue }
                        graph.owners[Self.lexical(url), default: []].insert(name)
                        if isa == "PBXSourcesBuildPhase" { graph.compiled[Self.lexical(url), default: []].insert(name) }
                    }
                }
            }
            let productType = target["productType"] as? String ?? ""
            graph.targets[name] = Target(name: name, productType: productType, edges: edges)
            let configurations = (target["buildConfigurationList"] as? String).flatMap { objects[$0]?["buildConfigurations"] as? [String] } ?? []
            let configured = configurations.map { objects[$0]?["buildSettings"] as? [String: Any] ?? [:] }
            for key in Self.readSettings {
                let setting = configured.filter { $0.keys.contains { Self.names($0, key) } }
                guard !setting.isEmpty else { continue }
                var read = Setting(isPartial: setting.count < configured.count)
                for settings in setting { read.values.formUnion(Self.values(of: key, in: settings)) }
                graph.settings[key, default: [:]][name] = read
            }
            for group in target["fileSystemSynchronizedGroups"] as? [String] ?? [] {
                guard let url = location(group) else { graph.unmodeled = "a folder of \(name) isn't in the project folder"; continue }
                let excepted = (objects[group]?["exceptions"] as? [String] ?? []).flatMap { objects[$0]?["membershipExceptions"] as? [String] ?? [] }
                graph.addFolder(Self.lexical(url), targets: [name], excepted: excepted)
            }
        }
        return graph
    }

    /// The JSON format's base for the products targets build.
    static let productsBase = "<PRODUCTS>/"

    /// The build phases that build on another target's product, and how: linking it, or copying it in.
    static let productPhases: [String: Edge] = ["PBXFrameworksBuildPhase": .linked, "PBXCopyFilesBuildPhase": .embedded]

    /// Whether a build-folder file is a product a target builds, by its extension.
    static func isProduct(_ path: String) -> Bool {
        ["framework", "a", "dylib", "bundle", "app", "appex", "xctest", "xpc"].contains((path as NSString).pathExtension)
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

    /// Whether a settings key sets `setting`, a conditional one (`PRODUCT_MODULE_NAME[config=Debug]`) too.
    static func names(_ key: String, _ setting: String) -> Bool {
        key == setting || key.hasPrefix(setting + "[")
    }

    /// The values `settings` give `setting`, its conditional keys' included.
    static func values(of setting: String, in settings: [String: Any]) -> Set<String> {
        Set(settings.filter { names($0.key, setting) }.compactMap { $0.value as? String })
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
        graph.products = producers
        func targetName(_ reference: Any) -> String? {
            guard let text = reference as? String ?? (reference as? [String: Any]).flatMap({ $0["build-phase"] as? String ?? $0["target"] as? String }) else { return nil }
            let name = String(text.split(separator: "/").first ?? "")
            return names.contains(name) ? name : namesByID[name]
        }
        for target in targets {
            guard let name = target["name"] as? String else { continue }
            var edges: [String: Set<Edge>] = [:]
            var references: [(reference: Any, edge: Edge)] = (target["dependencies"] as? [Any] ?? []).map { ($0, .named) }
            if let host = target["test-host-target"] { references.append((host, .testHost)) }
            for (reference, edge) in references {
                if let dependedOn = targetName(reference) {
                    edges[dependedOn, default: []].insert(edge)
                } else if let other = reference as? String {
                    // A target this project doesn't define: another project's, by name, among those the workspace reads.
                    graph.external[name, default: []].insert(other)
                } else {
                    graph.unmodeled = "\(name) depends on a target the reading can't resolve"
                }
            }
            let productType = target["product-type"] as? String ?? ""
            graph.targets[name] = Target(name: name, productType: productType, edges: edges)
            let settings = target["build-settings"] as? [String: Any] ?? [:]
            for key in Self.readSettings where settings.keys.contains(where: { Self.names($0, key) }) {
                // A conditional key alone sets it for the configurations it names, and leaves the others to the default.
                graph.settings[key, default: [:]][name] = Setting(values: Self.values(of: key, in: settings), isPartial: settings[key] == nil)
            }
            if let product = target["product"] as? String { graph.productFiles[name] = (product as NSString).lastPathComponent }
        }
        func walk(_ nodes: [[String: Any]], in base: URL) {
            for node in nodes {
                let path = node["path"] as? String
                // A path from another base is no file of the project's. A product, `<PRODUCTS>/Core.framework`, links the target
                // that builds it to each target it's a member of, entry or not; a system framework links nothing of ours.
                if let path, path.hasPrefix("<") {
                    // The reader doesn't read a member's phase yet, so a product a target is a member of counts as linked,
                    // as it always has, until the format is reviewed (docs/findings.md, *The module graph*).
                    if path.hasPrefix(Self.productsBase) {
                        for member in (node["target-membership"] as? [Any] ?? []).compactMap(targetName) {
                            graph.productEdges[member, default: [:]][(path as NSString).lastPathComponent, default: []].insert(.linked)
                        }
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
                    for target in membership {
                        graph.owners[Self.lexical(url), default: []].insert(target)
                        graph.compiled[Self.lexical(url), default: []].insert(target)
                    }
                }
            }
        }
        walk(project["files"] as? [[String: Any]] ?? [], in: URL(fileURLWithPath: ProjectLayout.canonical(folder)))
        return graph
    }
}
