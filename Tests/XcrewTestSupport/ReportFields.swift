import Foundation
import XcrewCore

/// A report as tests made and read it before its states were one value: `isUnread`, `backgroundTask` and
/// `isVerdictOnly` for `reading`, and `pinNote` and `pin` for `xcodePinNote`, each nil but for its own. A combination no
/// report can hold, as a task with no `isUnread`, stops the test.
extension Report {
    public init(ok: Bool, detail: String? = nil, durationMs: Int? = nil, tests: Int? = nil, failures: [ToolOutput.Failure], result: String? = nil, notes: [String], repeated: [ResultBundle.Repeated]? = nil, passed: [PassedTest]? = nil, isUnread: Bool? = nil, bundle: String? = nil, pinNote: String? = nil, pin: String? = nil, backgroundTask: String? = nil, isVerdictOnly: Bool? = nil, cause: String? = nil, concurrency: ConcurrencySummary? = nil, scheme: String? = nil) {
        precondition(backgroundTask == nil || isUnread == true, "a task is only an unread report's")
        precondition(isVerdictOnly != true || isUnread != true, "a report is unread or verdict-only, not both")
        precondition(pin == nil || pinNote != nil, "a pin is only a pin note's")
        let reading: Reading = isVerdictOnly == true ? .verdictOnly : isUnread == true ? .unread(task: backgroundTask) : .result
        self.init(ok: ok, detail: detail, durationMs: durationMs, tests: tests, failures: failures, result: result, notes: notes, repeated: repeated, passed: passed, reading: reading, bundle: bundle, xcodePinNote: pinNote.map { PinNote(note: $0, pin: pin) }, cause: cause, concurrency: concurrency, scheme: scheme)
    }

    /// True for a report that read nothing; nil otherwise, as the JSON writes it.
    public var isUnread: Bool? { reading.isUnread ? true : nil }
    /// The task an unread report's handle names.
    public var backgroundTask: String? { if case let .unread(task) = reading { task } else { nil } }
    /// True for a report read from a run log's verdict alone; nil otherwise.
    public var isVerdictOnly: Bool? { reading == .verdictOnly ? true : nil }
    /// The note on another Xcode than the pin's.
    public var pinNote: String? { xcodePinNote?.note }
    /// The pin that note names.
    public var pin: String? { xcodePinNote?.pin }
}
