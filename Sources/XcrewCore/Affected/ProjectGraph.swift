import Foundation

/// What a project file says about which target owns each file and which targets depend on which: the facts affected
/// tests need, in either format, `project.pbxproj` or Xcode 27.2's `project.xcproj` (docs/findings.md, *Affected
/// tests*). Whatever the reading meets and doesn't model is kept as a reason, which runs everything.
struct ProjectGraph: Sendable {
    struct Target: Sendable, Equatable {
        let name: String
        let isTest: Bool
        /// A UI test bundle, `…bundle.ui-testing`: it drives the app on a simulator, unlike a unit test bundle.
        let isUITest: Bool
        /// The targets it builds on: its dependencies and, for a test bundle, the app it runs in.
        var dependencies: Set<String>
        /// The product type without `com.apple.product-type.`, as both formats name it: `framework`, `application`.
        let kind: String

        init(name: String, isTest: Bool, isUITest: Bool, dependencies: Set<String>, kind: String) {
            (self.name, self.isTest, self.isUITest, self.dependencies, self.kind) = (name, isTest, isUITest, dependencies, kind)
        }

        /// A target as a project file declares it: what kind it is comes from its product type, in either format.
        init(name: String, productType: String, dependencies: Set<String>) {
            let kind = productType.hasPrefix(Self.productTypePrefix) ? String(productType.dropFirst(Self.productTypePrefix.count)) : productType
            self.init(name: name, isTest: productType.contains("test"), isUITest: productType.contains("ui-testing"), dependencies: dependencies, kind: kind)
        }

        static let productTypePrefix = "com.apple.product-type."
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
    /// Each product a target here builds, by its file name: `Core.framework`.
    var products: [String: String] = [:]
    /// Products a target links that no target in this project builds, for the workspace to resolve across projects.
    var links: [String: Set<String>] = [:]
    /// Of `links`, the products a target only copies into its own, an app embedding a framework it doesn't link: Tuist
    /// embeds every framework below an app's dependencies this way.
    var embedsOnly: [String: Set<String>] = [:]
    /// Targets in other projects a target depends on, by name, through a proxy into that project, for the workspace to
    /// resolve.
    var external: [String: Set<String>] = [:]
    /// The values a target's own settings give `PRODUCT_MODULE_NAME`, across its configurations, by target.
    var moduleNameSettings: [String: Set<String>] = [:]
    /// The targets whose settings give `PRODUCT_MODULE_NAME` for some configurations only.
    var partialModuleNames: Set<String> = []
    /// Each target's product, by its file name: `Core.framework`.
    var productFiles: [String: String] = [:]
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
            if let product = (target["productReference"] as? String).flatMap({ objects[$0]?["path"] as? String }) {
                productOwners[(product as NSString).lastPathComponent] = name
                graph.productFiles[name] = (product as NSString).lastPathComponent
            }
        }
        graph.products = productOwners
        for (id, target) in natives {
            guard let name = names[id] else { continue }
            var dependencies = Set<String>()
            for dependency in target["dependencies"] as? [String] ?? [] {
                if let targetID = objects[dependency]?["target"] as? String, let dependedOn = names[targetID] {
                    dependencies.insert(dependedOn)
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
            graph.links[name, default: []].formUnion(testHosts(of: target, in: objects))
            var linked = Set<String>(), copied = Set<String>()
            for phase in target["buildPhases"] as? [String] ?? [] {
                let isa = objects[phase]?["isa"] as? String ?? ""
                let links = Self.linkPhases.contains(isa)
                for buildFile in objects[phase]?["files"] as? [String] ?? [] {
                    guard let reference = objects[buildFile]?["fileRef"] as? String else { continue }
                    let files = (objects[reference]?["isa"] as? String) == "PBXVariantGroup" ? (objects[reference]?["children"] as? [String] ?? []) : [reference]
                    for file in files {
                        // Linking or embedding another target's product depends on it, entry or not: Xcode finds it implicitly.
                        // Anything else in the build folder, a file a script writes, is no product and no file of the project's.
                        if objects[file]?["sourceTree"] as? String == "BUILT_PRODUCTS_DIR", let product = objects[file]?["path"] as? String {
                            if links, Self.isProduct(product) {
                                let file = (product as NSString).lastPathComponent
                                graph.links[name, default: []].insert(file)
                                if isa == "PBXCopyFilesBuildPhase" { copied.insert(file) } else { linked.insert(file) }
                            }
                            continue
                        }
                        guard let url = location(file) else { continue }
                        graph.owners[Self.lexical(url), default: []].insert(name)
                    }
                }
            }
            let embedsOnly = copied.subtracting(linked)
            if !embedsOnly.isEmpty { graph.embedsOnly[name] = embedsOnly }
            let productType = target["productType"] as? String ?? ""
            graph.targets[name] = Target(name: name, productType: productType, dependencies: dependencies)
            let configurations = (target["buildConfigurationList"] as? String).flatMap { objects[$0]?["buildConfigurations"] as? [String] } ?? []
            let setting = configurations.filter { configuration in
                (objects[configuration]?["buildSettings"] as? [String: Any] ?? [:]).keys.contains { Self.isModuleNameKey($0) }
            }
            for configuration in setting {
                graph.addModuleNameSettings(objects[configuration]?["buildSettings"] as? [String: Any] ?? [:], of: name)
            }
            if !setting.isEmpty && setting.count < configurations.count { graph.partialModuleNames.insert(name) }
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

    /// The build phases that link or embed another target's product.
    static let linkPhases: Set = ["PBXFrameworksBuildPhase", "PBXCopyFilesBuildPhase"]

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

    /// Keeps `PRODUCT_MODULE_NAME` from a target's settings, a conditional one (`PRODUCT_MODULE_NAME[config=Debug]`) too.
    mutating func addModuleNameSettings(_ settings: [String: Any], of target: String) {
        for (key, value) in settings where Self.isModuleNameKey(key) {
            if let value = value as? String { moduleNameSettings[target, default: []].insert(value) }
        }
    }

    static func isModuleNameKey(_ key: String) -> Bool {
        key == "PRODUCT_MODULE_NAME" || key.hasPrefix("PRODUCT_MODULE_NAME[")
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
            var dependencies = Set<String>()
            for reference in (target["dependencies"] as? [Any] ?? []) + [target["test-host-target"]].compactMap({ $0 }) {
                if let dependedOn = targetName(reference) {
                    dependencies.insert(dependedOn)
                } else if let other = reference as? String {
                    // A target this project doesn't define: another project's, by name, among those the workspace reads.
                    graph.external[name, default: []].insert(other)
                } else {
                    graph.unmodeled = "\(name) depends on a target the reading can't resolve"
                }
            }
            let productType = target["product-type"] as? String ?? ""
            graph.targets[name] = Target(name: name, productType: productType, dependencies: dependencies)
            let settings = target["build-settings"] as? [String: Any] ?? [:]
            graph.addModuleNameSettings(settings, of: name)
            // A conditional key alone sets it for the configurations it names, and leaves the others to the default.
            if settings.keys.contains(where: Self.isModuleNameKey), settings["PRODUCT_MODULE_NAME"] == nil { graph.partialModuleNames.insert(name) }
            if let product = target["product"] as? String { graph.productFiles[name] = (product as NSString).lastPathComponent }
        }
        func walk(_ nodes: [[String: Any]], in base: URL) {
            for node in nodes {
                let path = node["path"] as? String
                // A path from another base is no file of the project's. A product, `<PRODUCTS>/Core.framework`, links the target
                // that builds it to each target it's a member of, entry or not; a system framework links nothing of ours.
                if let path, path.hasPrefix("<") {
                    if path.hasPrefix(Self.productsBase) {
                        for member in (node["target-membership"] as? [Any] ?? []).compactMap(targetName) { graph.links[member, default: []].insert((path as NSString).lastPathComponent) }
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
