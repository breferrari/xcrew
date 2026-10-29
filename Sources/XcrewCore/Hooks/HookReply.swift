import Foundation

/// A command hook's JSON reply; `context` reaches Claude.
public struct HookReply: Sendable, Equatable {
    public let event: HookEvent
    public let context: String

    public init(event: HookEvent, context: String) {
        self.event = event
        self.context = context
    }

    public var json: String {
        let object = ["hookSpecificOutput": ["hookEventName": event.name, "additionalContext": context]]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
