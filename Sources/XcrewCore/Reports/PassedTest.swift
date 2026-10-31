import Foundation

/// A test a run's results list as passed, as `Suite/test`, with the test bundle the result bundle files it under when it
/// names one: what the ledger turns a red test green from. Ordered by test, then target, a test with no target first.
public struct PassedTest: Sendable, Equatable, Codable, Comparable {
    public let test: String
    public let target: String?

    public init(test: String, target: String?) {
        self.test = test
        self.target = target
    }

    init(_ id: TestID, target: String? = nil) {
        self.init(test: id.shown, target: target)
    }

    public static func < (lhs: PassedTest, rhs: PassedTest) -> Bool {
        (lhs.test, lhs.target ?? "") < (rhs.test, rhs.target ?? "")
    }
}
