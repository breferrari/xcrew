import Foundation

/// The test plans a project's shared schemes run by default that test under more than one configuration, so a test can
/// fail under one and pass under another. Read from the schemes `TestSchemes` reads, never by walking the whole tree.
enum TestPlans {
    struct Configured: Sendable, Equatable {
        let plan: String
        /// The schemes whose default it is, in the order their names sort.
        let schemes: [String]
        let configurations: [String]
    }

    /// Each such plan once, in the order of the first scheme that runs it, from these containers and the projects their
    /// workspaces list.
    static func configured(containers: [URL]) -> [Configured] {
        var found: [(key: String, configured: Configured)] = []
        for container in TestSchemes.containers(from: containers) {
            let base = container.deletingLastPathComponent()
            for scheme in TestSchemes.sharedSchemes(of: container) {
                let references = ((try? scheme.document.nodes(forXPath: "//TestAction/TestPlans/TestPlanReference")) ?? []).compactMap { $0 as? XMLElement }
                // The plan a run takes when none is named: the default, or the only one.
                guard let reference = references.first(where: { $0.attribute(forName: "default")?.stringValue == "YES" }) ?? (references.count == 1 ? references.first : nil),
                      let location = reference.attribute(forName: "reference")?.stringValue
                else { continue }
                let file = TestSchemes.resolve(location, from: base)
                let key = TestSchemes.key(file)
                if let index = found.firstIndex(where: { $0.key == key }) {
                    let known = found[index].configured
                    found[index].configured = Configured(plan: known.plan, schemes: known.schemes + [scheme.name], configurations: known.configurations)
                    continue
                }
                let names = (TestSchemes.plan(at: file)?["configurations"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                guard names.count > 1 else { continue }
                found.append((key, Configured(plan: file.deletingPathExtension().lastPathComponent, schemes: [scheme.name], configurations: names)))
            }
        }
        return found.map(\.configured)
    }
}
