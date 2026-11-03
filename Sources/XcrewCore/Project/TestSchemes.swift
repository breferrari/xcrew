import Foundation

/// Which shared scheme runs a project's unit tests: the scheme setup gives the `unit` profile. Only
/// committed schemes count (`xcshareddata`), never one person's (`xcuserdata`). A target's product
/// type comes from `project.pbxproj` or Xcode 27.2's JSON `project.xcproj`; when neither says, the
/// answer is `unknown`, never a guess.
public enum TestSchemes {
    public enum Choice: Sendable, Equatable {
        case scheme(String)
        case none
        /// More than one scheme runs the most unit-test targets.
        case several([String])
        /// A scheme tests a target whose product type couldn't be read, so it might run unit tests.
        case unknown([String])
    }

    /// A shared scheme, the container whose scheme it is, from the project's root, and the targets it tests.
    public struct Scheme: Sendable, Equatable, Codable {
        public let name: String
        public let container: String
        public let targets: [String]
    }

    /// The shared schemes of `containers` and the projects their workspaces list that test something, and only targets
    /// in `targets`, the fewest first. A scheme whose test plan can't be read may test anything, so it isn't one.
    static func testingOnly(_ targets: Set<String>, in containers: [URL], from root: URL) -> [Scheme] {
        guard !targets.isEmpty else { return [] }
        return testing(in: containers, from: root).filter { Set($0.targets).isSubset(of: targets) }
    }

    /// Every shared scheme of `containers` and the projects their workspaces list that tests something, with the targets
    /// it tests, the fewest first. A scheme whose test plan can't be read may test anything, so it isn't one.
    static func testing(in containers: [URL], from root: URL) -> [Scheme] {
        let base = ProjectLayout.canonical(root) + "/"
        return Self.containers(from: containers).flatMap { container in
            let path = ProjectLayout.canonical(container)
            return tested(by: container).compactMap { name, tested -> Scheme? in
                let names = Set(tested.testables.map(\.name))
                guard tested.isWhole, !names.isEmpty else { return nil }
                return Scheme(name: name, container: path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path, targets: names.sorted())
            }
        }.sorted { ($0.targets.count, $0.name, $0.container) < ($1.targets.count, $1.name, $1.container) }
    }

    /// A target a scheme tests, and the project that holds it when the scheme says.
    struct Testable: Hashable {
        let name: String
        let project: String?
    }

    static let unitTest = "com.apple.product-type.bundle.unit-test"
    static let uiTest = "com.apple.product-type.bundle.ui-testing"
    static let application = "com.apple.product-type.application"
    /// Repository files are read without fetching anything they point to.
    static let xmlOptions: XMLNode.Options = [.nodeLoadExternalEntitiesNever]

    /// The scheme that runs the most unit-test targets; among those tied, `appScheme`.
    public static func choose(in container: URL, preferring appScheme: String?) -> Choice {
        let containers = containers(from: [container])
        let lookUp = productTypeLookup(for: containers)
        func type(of testable: Testable) -> String? { lookUp(testable.name, testable.project) }
        var runs: [String: Int] = [:], unsure: Set<String> = []
        for project in containers {
            for (name, document) in sharedSchemes(of: project) {
                let kinds = runByDefault(by: document, in: project).map(type(of:))
                let unitTests = kinds.count { $0 == unitTest }
                if unitTests > 0 { runs[name] = max(runs[name] ?? 0, unitTests) } else if kinds.contains(nil) { unsure.insert(name) }
            }
        }
        let found = widest(runs, preferring: appScheme)
        if found.isEmpty { return unsure.isEmpty ? .none : .unknown(unsure.sorted()) }
        return found.count == 1 ? .scheme(found[0]) : .several(found)
    }

    /// Of schemes by how many unit-test targets each runs, those that run the most, sorted; `appScheme` alone when it's
    /// among them.
    static func widest(_ unitTests: [String: Int], preferring appScheme: String?) -> [String] {
        guard let most = unitTests.values.max(), most > 0 else { return [] }
        let widest = unitTests.filter { $0.value == most }.keys.sorted()
        if let appScheme, widest.contains(appScheme) { return [appScheme] }
        return widest
    }

    /// A target's product type, by its name and the project a scheme says holds it; with no project, or one that doesn't
    /// have it, the type when only one of `containers` has a target of that name.
    static func productTypeLookup(for containers: [URL]) -> (_ target: String, _ project: String?) -> String? {
        let types = containers.reduce(into: [String: [String: String]]()) { types, project in
            types[key(project)] = productTypes(of: project)
        }
        return { target, project in
            if let project, let type = types[project]?[target] { return type }
            let anywhere = Set(types.values.compactMap { $0[target] })
            return anywhere.count == 1 ? anywhere.first : nil
        }
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

    /// Each shared scheme's testables that might run: its `TestableReference`s not skipped, and every target of its test
    /// plans, with whether every test plan each scheme names could be read.
    static func tested(by container: URL) -> [String: (testables: [Testable], isWhole: Bool)] {
        sharedSchemes(of: container).reduce(into: [:]) { schemes, scheme in
            schemes[scheme.name] = tested(by: scheme.document, in: container)
        }
    }

    /// What one parsed scheme of `container` tests, with whether every test plan it names could be read.
    static func tested(by document: XMLDocument, in container: URL) -> (testables: [Testable], isWhole: Bool) {
        let base = container.deletingLastPathComponent()
        do {
            let listed = testables(of: document, from: base)
            let plans = (try? document.nodes(forXPath: "//TestAction/TestPlans/TestPlanReference/@reference")) ?? []
            let planFiles = plans.compactMap(\.stringValue).map { resolve($0, from: base) }
            let planTargets = planFiles.flatMap { targets(ofPlan: $0, from: base) }
            return (listed + planTargets, planFiles.allSatisfy { plan(at: $0) != nil })
        }
    }

    /// The targets a scheme's test action lists itself, those it skips left out.
    static func testables(of document: XMLDocument, from base: URL) -> [Testable] {
        let references = (try? document.nodes(forXPath: "//TestAction/Testables/TestableReference[not(@skipped='YES')]/BuildableReference")) ?? []
        return references.compactMap { $0 as? XMLElement }.compactMap { reference -> Testable? in
            guard let name = reference.attribute(forName: "BlueprintName")?.stringValue else { return nil }
            return Testable(name: name, project: reference.attribute(forName: "ReferencedContainer")?.stringValue.map { key(resolve($0, from: base)) })
        }
    }

    /// What one parsed scheme of `container` runs when no test plan is named, each target once: its testables and its
    /// default plan's targets, as Xcode runs the plan a scheme marks default when none is named (Apple's "Organizing
    /// tests to improve feedback"), or its first plan when none is marked.
    static func runByDefault(by document: XMLDocument, in container: URL) -> [Testable] {
        let base = container.deletingLastPathComponent()
        let listed = testables(of: document, from: base)
        let plans = ((try? document.nodes(forXPath: "//TestAction/TestPlans/TestPlanReference")) ?? []).compactMap { $0 as? XMLElement }
        let plan = plans.first { $0.attribute(forName: "default")?.stringValue == "YES" } ?? plans.first
        let planTargets = plan?.attribute(forName: "reference")?.stringValue.map { targets(ofPlan: resolve($0, from: base), from: base) } ?? []
        var seen: Set<Testable> = []
        return (listed + planTargets).filter { seen.insert($0).inserted }
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
