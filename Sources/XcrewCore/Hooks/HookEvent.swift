import Foundation

/// The JSON a Claude Code command hook receives on stdin; xcrew reads only what it needs.
public struct HookEvent: Sendable, Equatable {
    public let name: String
    public let cwd: String?
    /// The session the event is of: `session_id` in the hook's input.
    public let session: String?

    public init(name: String, cwd: String? = nil, session: String? = nil) {
        self.name = name
        self.cwd = cwd
        self.session = session
    }

    public init(json: Data) {
        let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:]
        self.init(name: object["hook_event_name"] as? String ?? "SessionStart", cwd: object["cwd"] as? String, session: object["session_id"] as? String)
    }
}
