import Foundation

/// The test plans a project's shared schemes run by default that test under more than one configuration, so a test can
/// fail under one and pass under another. Read from the schemes `TestSchemes` reads, never by walking the whole tree.
enum TestPlans {
    struct Configured: Sendable, Equatable {
        let plan: String
        /// The schemes whose default it is, each once, in the order their names sort.
        let schemes: [String]
        let configurations: [String]
    }

    /// Schemes read at most: the briefing reads them at every session start, and a large modular app has hundreds.
    static let mostSchemes = 50

    /// Each such plan once, in the order of the first scheme that runs it, from these containers and the projects their
    /// workspaces list; each plan file read once, whichever schemes name it. `complete` is false when reading stopped at
    /// `mostSchemes` with schemes left unread.
    static func configured(containers: [URL]) -> (plans: [Configured], complete: Bool) {
        var complete = true
        var order: [String] = []
        var plans: [String: (name: String, configurations: [String], schemes: Set<String>)] = [:]
        var read = 0
        scan: for container in TestSchemes.containers(from: containers) {
            let base = container.deletingLastPathComponent()
            for file in TestSchemes.sharedSchemeFiles(of: container) {
                guard read < mostSchemes else {
                    complete = false
                    break scan
                }
                read += 1
                guard let scheme = TestSchemes.parse(scheme: file) else { continue }
                let references = ((try? scheme.document.nodes(forXPath: "//TestAction/TestPlans/TestPlanReference")) ?? []).compactMap { $0 as? XMLElement }
                // The plan a run takes when none is named: the default, or the only one.
                guard let reference = references.first(where: { $0.attribute(forName: "default")?.stringValue == "YES" }) ?? (references.count == 1 ? references.first : nil),
                      let location = reference.attribute(forName: "reference")?.stringValue
                else { continue }
                let plan = TestSchemes.resolve(location, from: base)
                let key = TestSchemes.key(plan)
                if plans[key] == nil {
                    let names = (TestSchemes.plan(at: plan)?["configurations"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                    plans[key] = (plan.deletingPathExtension().lastPathComponent, names, [])
                    order.append(key)
                }
                plans[key]?.schemes.insert(scheme.name)
            }
        }
        let configured = order.compactMap { key -> Configured? in
            guard let found = plans[key], found.configurations.count > 1 else { return nil }
            return Configured(plan: found.name, schemes: found.schemes.sorted(), configurations: found.configurations)
        }
        return (configured, complete)
    }
}
