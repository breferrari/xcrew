import Foundation

/// What a failed build left to explain it: the errors it reported, and what a cause may look at on the Mac to confirm
/// itself. The build log is found only when a cause asks for it.
public struct FailureEvidence: Sendable {
    public let errors: [ReportedError]
    let runner: any CommandRunning
    /// The build log the failure came from, if one is known.
    let log: @Sendable () -> String?
    /// The project's root, resolved, against which an error's file is the code's.
    let root: String

    public init(errors: [ReportedError], project: Project, runner: any CommandRunning, log: @escaping @Sendable () -> String?) {
        self.errors = errors
        self.runner = runner
        self.log = log
        root = project.canonicalRoot
    }

    /// The errors whose message starts with `words` and that point at none of the project's own files: one there is the
    /// code's, however alike its words, since an `#error` can quote them.
    func errors(startingWith words: String) -> [ReportedError] {
        errors.filter { $0.message.hasPrefix(words) && !$0.isInside(root: root) }
    }
}
