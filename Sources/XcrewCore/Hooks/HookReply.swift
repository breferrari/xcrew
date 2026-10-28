import Foundation

/// A command hook's JSON reply. `context` reaches Claude; `systemMessage` is shown to the person.
public struct HookReply: Sendable, Equatable {
    public let event: HookEvent
    public let context: String
    public let systemMessage: String?

    public init(event: HookEvent, context: String, systemMessage: String? = nil) {
        self.event = event
        self.context = context
        self.systemMessage = systemMessage
    }

    public var json: String {
        var object: [String: Any] = ["hookSpecificOutput": ["hookEventName": event.name, "additionalContext": context]]
        if let systemMessage { object["systemMessage"] = systemMessage }
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
