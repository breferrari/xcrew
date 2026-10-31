import Foundation

/// A test a run's results list as passed, as `Suite/test`, with the test bundle the result bundle files it under when it
/// names one: what the ledger turns a red test green from.
public struct PassedTest: Sendable, Equatable, Codable {
    public let test: String
    public let target: String?

    public init(test: String, target: String?) {
        self.test = test
        self.target = target
    }

    /// By test, then target, a test with no target first: one order whatever order the results gave.
    static func sorted(_ tests: [PassedTest]) -> [PassedTest] {
        tests.sorted { ($0.test, $0.target ?? "") < ($1.test, $1.target ?? "") }
    }
}
