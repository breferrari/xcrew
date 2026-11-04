import Foundation

/// The test plans a project's shared schemes run by default that test under more than one configuration, so a test can
/// fail under one and pass under another. Read from the schemes `TestSchemes` reads, never by walking the whole tree.
public enum TestPlans {
    /// Where every plan of several configurations, and every scheme it's the default of, is listed.
    static let listedBy = "`xcrew plans` lists them all"

    struct Configured: Sendable, Equatable {
        let plan: String
        /// The plan's file.
        let file: String
        /// The schemes whose default it is, each once, in the order their names sort.
        let schemes: [String]
        let configurations: [String]

        /// The plan, the schemes it's the default of, a few and the rest counted with where they're listed, and its
        /// configurations, in a sentence: what a hook's context, which has a cap, and a test result say.
        var sentence: String { sentence(schemesRest: TestPlans.listedBy) }

        /// The sentence with every scheme it's the default of, as `xcrew plans` gives it; a few and the rest counted with
        /// `schemesRest` when one is given.
        func sentence(schemesRest: String?) -> String {
            let named = String(ResultBundle.listed(schemes.map { "`\($0)`" }, rest: schemesRest).dropFirst(2))
            return "Test plan `\(plan)`, the default of \(schemes.count == 1 ? "scheme" : "schemes") \(named), runs each test under each of its configurations\(ResultBundle.listed(configurations, rest: "`\(file)` lists them all"))."
        }
    }

    /// Every plan of several configurations the project's schemes run by default, a line each with every scheme it's the
    /// default of, as `xcrew plans` prints them; nil when there's none.
    public static func listing(for project: Project) -> String? {
        let plans = configured(containers: project.repositoryContainers)
        return plans.isEmpty ? nil : plans.map { $0.sentence(schemesRest: nil) }.joined(separator: "\n")
    }

    /// The plan of several configurations a scheme runs by default, if any, from the project's containers.
    static func configured(forScheme scheme: String, in project: Project) -> Configured? {
        configured(containers: project.repositoryContainers).first { $0.schemes.contains(scheme) }
    }

    /// Each such plan once, in the order of the first scheme that runs it, from these containers and the projects their
    /// workspaces list, every shared scheme read, however many: each plan file read once, whichever schemes name it.
    static func configured(containers: [URL]) -> [Configured] {
        var order: [String] = []
        var plans: [String: (name: String, file: String, configurations: [String], schemes: Set<String>)] = [:]
        for container in TestSchemes.containers(from: containers) {
            let base = container.deletingLastPathComponent()
            for file in TestSchemes.sharedSchemeFiles(of: container) {
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
                    plans[key] = (plan.deletingPathExtension().lastPathComponent, plan.path, names, [])
                    order.append(key)
                }
                plans[key]?.schemes.insert(scheme.name)
            }
        }
        return order.compactMap { key -> Configured? in
            guard let found = plans[key], found.configurations.count > 1 else { return nil }
            return Configured(plan: found.name, file: found.file, schemes: found.schemes.sorted(), configurations: found.configurations)
        }
    }
}
