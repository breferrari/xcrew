import Foundation

extension Report {
    /// What a report could read of a build, test or run call, one of three: the call's outcome, none, or a run log's
    /// alone. Written as the mod reads it, `isUnread`, `backgroundTask` and `isVerdictOnly`, each absent but for its own.
    public enum Reading: Sendable, Equatable {
        /// The server's result, or a log and its result bundle: the run's own outcome.
        case result
        /// No outcome: a result that holds nothing in its server's own forms and isn't an error, as the handle Claude Code
        /// answers a call it moved to the background with, the task's id when the handle names one; or a task that ended
        /// with nothing to read.
        case unread(task: String?)
        /// The outcome comes from a run log alone, its last verdict or the error xcodebuild ended it with, with no result or
        /// bundle read: no test's own result.
        case verdictOnly

        /// Whether it's `unread`.
        public var isUnread: Bool {
            if case .unread = self { true } else { false }
        }
    }
}
