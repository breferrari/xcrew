import Foundation

/// Which shared scheme runs a project's unit tests: the scheme setup gives the `unit` profile. Only
/// committed schemes count (`xcshareddata`), never one person's (`xcuserdata`). A target's product
/// type comes from `project.pbxproj` or Xcode 27.2's JSON `project.xcproj`; when neither says, the
/// answer is `unknown`, never a guess.
public enum TestSchemes {
    public enum Choice: Sendable, Equatable {
        case scheme(String)
        case none
        /// More than one scheme runs unit tests.
        case several([String])
        /// A scheme tests a target whose product type couldn't be read, so it might run unit tests.
        case unknown([String])
    }

    /// A target a scheme tests, and the project that holds it when the scheme says.
    struct Testable: Hashable {
        let name: String
        let project: String?
    }

    static let unitTest = "com.apple.product-type.bundle.unit-test"
    /// Repository files are read without fetching anything they point to.
    static let xmlOptions: XMLNode.Options = [.nodeLoadExternalEntitiesNever]

    public static func choose(in container: URL, preferring appScheme: String?) -> Choice {
        let containers = containers(from: [container])
        let types = containers.reduce(into: [String: [String: String]]()) { types, project in
            types[key(project)] = productTypes(of: project)
        }
        func type(of testable: Testable) -> String? {
            if let project = testable.project, let type = types[project]?[testable.name] { return type }
            let anywhere = Set(types.values.compactMap { $0[testable.name] })
            return anywhere.count == 1 ? anywhere.first : nil
        }
        var runs: Set<String> = [], unsure: Set<String> = []
        for project in containers {
            for (name, testables) in schemes(of: project) {
                let kinds = testables.map(type(of:))
                if kinds.contains(unitTest) { runs.insert(name) } else if kinds.contains(nil) { unsure.insert(name) }
            }
        }
        if let appScheme, runs.contains(appScheme) { return .scheme(appScheme) }
        let found = runs.sorted()
        if found.isEmpty { return unsure.isEmpty ? .none : .unknown(unsure.sorted()) }
        return found.count == 1 ? .scheme(found[0]) : .several(found)
    }

    /// The containers whose schemes count: these, then the projects their workspaces list, each once.
    static func containers(from roots: [URL]) -> [URL] {
        var seen: Set<String> = []
        return (roots + roots.flatMap(projects(in:))).filter { seen.insert(key($0)).inserted }
    }

    /// A container's shared schemes, parsed, in the order of their names.
    static func sharedSchemes(of container: URL) -> [(name: String, document: XMLDocument)] {
        sharedSchemeFiles(of: container).compactMap(parse(scheme:))
    }

    /// A container's shared scheme files, unparsed, in the order of their names.
    static func sharedSchemeFiles(of container: URL) -> [URL] {
        let folder = container.appending(path: "xcshareddata/xcschemes")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "xcscheme" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func parse(scheme file: URL) -> (name: String, document: XMLDocument)? {
        (try? XMLDocument(contentsOf: file, options: xmlOptions)).map { (file.deletingPathExtension().lastPathComponent, $0) }
    }

    /// A test plan as its JSON reads.
    static func plan(at file: URL) -> [String: Any]? {
        (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    static func key(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    /// The projects a workspace lists, each path relative to the groups around it.
    static func projects(in container: URL) -> [URL] {
        guard container.pathExtension == "xcworkspace",
              let document = try? XMLDocument(contentsOf: container.appending(path: "contents.xcworkspacedata"), options: xmlOptions),
              let root = document.rootElement() else { return [] }
        func walk(_ element: XMLElement, from folder: URL) -> [URL] {
            (element.children ?? []).compactMap { $0 as? XMLElement }.flatMap { child -> [URL] in
                let location = child.attribute(forName: "location")?.stringValue
                switch child.name {
                case "FileRef":
                    guard let location, location.hasSuffix(".xcodeproj") else { return [] }
                    return [resolve(location, from: folder)]
                case "Group":
                    return walk(child, from: location.map { resolve($0, from: folder) } ?? folder)
                default:
                    return []
                }
            }
        }
        return walk(root, from: container.deletingLastPathComponent())
    }

    /// A workspace or scheme location (`group:`, `container:` or `absolute:`), resolved from the folder that names it.
    static func resolve(_ location: String, from folder: URL) -> URL {
        let path = location.firstIndex(of: ":").map { String(location[location.index(after: $0)...]) } ?? location
        return location.hasPrefix("absolute:") ? URL(fileURLWithPath: path) : folder.appending(path: path)
    }

    /// Each shared scheme's testables that run: its `TestableReference`s not skipped, and every target of its test plans.
    static func schemes(of container: URL) -> [String: [Testable]] {
        let base = container.deletingLastPathComponent()
        return sharedSchemes(of: container).reduce(into: [:]) { schemes, scheme in
            let document = scheme.document
            let references = (try? document.nodes(forXPath: "//TestAction/Testables/TestableReference[not(@skipped='YES')]/BuildableReference")) ?? []
            let testables = references.compactMap { $0 as? XMLElement }.compactMap { reference -> Testable? in
                guard let name = reference.attribute(forName: "BlueprintName")?.stringValue else { return nil }
                return Testable(name: name, project: reference.attribute(forName: "ReferencedContainer")?.stringValue.map { key(resolve($0, from: base)) })
            }
            let plans = (try? document.nodes(forXPath: "//TestAction/TestPlans/TestPlanReference/@reference")) ?? []
            let planTargets = plans.compactMap(\.stringValue).flatMap { targets(ofPlan: resolve($0, from: base), from: base) }
            schemes[scheme.name] = testables + planTargets
        }
    }

    static func targets(ofPlan file: URL, from base: URL) -> [Testable] {
        guard let entries = plan(at: file)?["testTargets"] as? [[String: Any]] else { return [] }
        return entries.filter { $0["enabled"] as? Bool ?? true }.compactMap { entry in
            guard let target = entry["target"] as? [String: Any], let name = target["name"] as? String else { return nil }
            return Testable(name: name, project: (target["containerPath"] as? String).map { key(resolve($0, from: base)) })
        }
    }

    /// Target name → product type, from whichever project file the project has.
    static func productTypes(of project: URL) -> [String: String] {
        if let data = try? Data(contentsOf: project.appending(path: ProjectLayout.pbxproj)),
           let plist = try? PropertyListDecoder().decode(PBXProject.self, from: data) {
            return plist.objects.values.filter { $0.isa == "PBXNativeTarget" }.reduce(into: [:]) { types, target in
                if let name = target.name, let type = target.productType { types[name] = type }
            }
        }
        if let data = try? Data(contentsOf: project.appending(path: ProjectLayout.jsonProject)),
           let json = try? JSONSerialization.jsonObject(with: data) {
            var types: [String: String] = [:]
            collectTargets(json, into: &types)
            return types
        }
        return [:]
    }

    /// The part of `project.pbxproj` read here: each object's kind, and a target's name and product type.
    struct PBXProject: Decodable {
        struct Object: Decodable {
            let isa: String
            let name: String?
            let productType: String?
        }
        let objects: [String: Object]
    }

    /// Every object with a `name` and a product type, wherever it sits: the nesting comes from the format's
    /// source, not a file Xcode wrote here. The JSON format abbreviates `com.apple.product-type.` product
    /// types as `product-type`, and spells others out as `full-product-type`.
    static func collectTargets(_ value: Any, into types: inout [String: String]) {
        if let object = value as? [String: Any] {
            if let name = object["name"] as? String {
                if let short = object["product-type"] as? String { types[name] = "com.apple.product-type." + short }
                else if let full = object["full-product-type"] as? String { types[name] = full }
            }
            object.values.forEach { collectTargets($0, into: &types) }
        } else if let array = value as? [Any] {
            array.forEach { collectTargets($0, into: &types) }
        }
    }
}
