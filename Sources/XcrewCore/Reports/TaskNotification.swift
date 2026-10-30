import Foundation

/// A background task's notification, as Claude Code hands it to Claude when the task ends: its status, and the result
/// between `<result>` lines. Claude Code's own text, undocumented (docs/findings.md, *A call moved to the background*).
public struct TaskNotification: Sendable, Equatable {
    /// `completed`, `failed`, `killed`, or another word Claude Code uses.
    public var status: String
    let text: String
    let body: Range<String.Index>?

    /// The first notification in `text`; nil when it has no status. The result may hold anything, tags included, so it
    /// runs to the last `</result>` line before its notification's end.
    public init?(_ text: String) {
        guard let opening = text.range(of: "<status>"), let closing = text.range(of: "</status>", range: opening.upperBound..<text.endIndex) else { return nil }
        self.text = text
        status = String(text[opening.upperBound..<closing.lowerBound])
        let ending = text.range(of: "</task-notification>", range: closing.upperBound..<text.endIndex)?.lowerBound ?? text.endIndex
        if let start = text.range(of: "<result>\n", range: closing.upperBound..<ending), let end = text.range(of: "\n</result>", options: .backwards, range: start.upperBound..<ending) {
            body = start.upperBound..<end.lowerBound
        } else {
            body = nil
        }
    }

    /// The task's result; nil when the notification carries none.
    public var result: String? { body.map { String(text[$0]) } }

    /// The result of a task that completed: one that failed or was killed has none of the server's to read.
    public var completedResult: String? { status == "completed" ? result : nil }

    /// The notification with `result` in its result's place.
    public func replacingResult(with result: String) -> String {
        guard let body else { return text }
        return text.replacingCharacters(in: body, with: result)
    }
}
