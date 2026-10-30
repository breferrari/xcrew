import Foundation

/// One way a build fails because of the Mac. To add one, write a type in `Why/` and list it in `Why.causes`.
protocol MachineCause: Sendable {
    /// What happened and the fix, when the failure's errors show this cause and the Mac confirms it; nil otherwise.
    func explanation(of failure: FailureEvidence) async -> String?
}
