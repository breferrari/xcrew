import Foundation

/// The JSON a Claude Code command hook receives on stdin; xcrew reads only what it needs.
public struct HookEvent: Sendable, Equatable {
    public let name: String
    public let cwd: String?

    public init(name: String, cwd: String? = nil) {
        self.name = name
        self.cwd = cwd
    }

    public init(json: Data) {
        let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:]
        self.init(name: object["hook_event_name"] as? String ?? "SessionStart", cwd: object["cwd"] as? String)
    }
}
