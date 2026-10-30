import Foundation

/// The shared schemes that test only targets a change can break. Where a project keeps a scheme per module beside one
/// that tests every module, a test with a module's scheme builds that module and what it uses, while `-only-testing:`
/// on the wide scheme still builds every module it tests (a field report: a whole app built for one module's tests).
public enum ModuleSchemes {
    public struct Scheme: Sendable, Equatable, Codable {
        public let name: String
        /// How many targets it tests.
        public let targets: Int
    }

    /// The shared schemes of `containers` and the projects their workspaces list that test something, and only targets
    /// in `selections`, the fewest targets first.
    public static func testingOnly(_ selections: Set<String>, in containers: [URL]) -> [Scheme] {
        let schemes = TestSchemes.containers(from: containers).reduce(into: [String: Set<String>]()) { all, project in
            for (name, testables) in TestSchemes.schemes(of: project) { all[name, default: []].formUnion(testables.map(\.name)) }
        }
        return schemes.filter { !$0.value.isEmpty && $0.value.isSubset(of: selections) }
            .map { Scheme(name: $0.key, targets: $0.value.count) }
            .sorted { ($0.targets, $0.name) < ($1.targets, $1.name) }
    }
}
