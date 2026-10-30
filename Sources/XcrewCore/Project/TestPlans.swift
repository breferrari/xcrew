import Foundation

/// The test plans a project's shared schemes run that test under more than one configuration, so a test can fail under
/// one and pass under another. Read from the schemes of the containers nearest the root and the projects their
/// workspaces list, as setup reads them (`TestSchemes`), never by walking the whole tree.
enum TestPlans {
    struct Configured: Sendable, Equatable {
        let scheme: String
        let plan: String
        let configurations: [String]
    }

    static func configured(in project: Project) -> [Configured] {
        let containers = project.layout(.repository).containers.map { project.root.appending(path: $0) }
        var seen: Set<String> = []
        return (containers + containers.flatMap(TestSchemes.projects))
            .filter { seen.insert(TestSchemes.key($0)).inserted }
            .flatMap(plans(of:))
    }

    /// Each shared scheme's default test plan, or its only one, when it has several configurations.
    static func plans(of container: URL) -> [Configured] {
        let base = container.deletingLastPathComponent()
        let folder = container.appending(path: "xcshareddata/xcschemes")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "xcscheme" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { file in
            guard let document = try? XMLDocument(contentsOf: file, options: TestSchemes.xmlOptions) else { return nil }
            let references = ((try? document.nodes(forXPath: "//TestAction/TestPlans/TestPlanReference")) ?? []).compactMap { $0 as? XMLElement }
            guard let reference = references.first(where: { $0.attribute(forName: "default")?.stringValue == "YES" }) ?? (references.count == 1 ? references.first : nil),
                  let location = reference.attribute(forName: "reference")?.stringValue
            else { return nil }
            let plan = TestSchemes.resolve(location, from: base)
            let names = configurations(of: plan)
            guard names.count > 1 else { return nil }
            return Configured(scheme: file.deletingPathExtension().lastPathComponent, plan: plan.deletingPathExtension().lastPathComponent, configurations: names)
        }
    }

    /// A test plan's configurations by name, in the order it lists them.
    static func configurations(of plan: URL) -> [String] {
        guard let data = try? Data(contentsOf: plan), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return (json["configurations"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
    }
}
