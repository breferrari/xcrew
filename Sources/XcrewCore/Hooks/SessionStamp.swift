import Foundation

/// What a Claude Code session has reported to xcrew, by its session id: the version whose rules its start hook gave
/// Claude, and the version of the mod loaded in it. The doctor reads it for the session it runs in, named by Claude
/// Code's `CLAUDE_CODE_SESSION_ID` (docs/findings.md, *Which session the doctor checks*).
public struct SessionStamp: Codable, Equatable, Sendable {
    public var briefing: String?
    public var mod: String?

    public init(briefing: String? = nil, mod: String? = nil) {
        self.briefing = briefing
        self.mod = mod
    }

    /// The session the doctor runs in: Claude Code sets the variable for its Bash tool's commands and its hooks, never
    /// in a terminal of one's own.
    public static func session(on machine: Machine) -> String? {
        machine.value("CLAUDE_CODE_SESSION_ID")
    }

    /// How long a stamp no session end removed is kept, as after a crash: the two weeks xcrew keeps its other unused
    /// cache entries for. A choice, not a measurement; #395 reviews xcrew's retention ages.
    static let keptDays = 14

    public static func read(_ session: String, on machine: Machine) -> SessionStamp? {
        (try? Data(contentsOf: file(session, on: machine))).flatMap { try? JSONDecoder().decode(SessionStamp.self, from: $0) }
    }

    /// Changes a session's stamp, kept in xcrew's cache. A session's first stamp removes the ones left too long.
    public static func record(_ session: String, on machine: Machine, _ change: (inout SessionStamp) -> Void) {
        let before = read(session, on: machine)
        var stamp = before ?? SessionStamp()
        change(&stamp)
        guard stamp != before, let encoded = try? JSONEncoder().encode(stamp) else { return }
        let url = file(session, on: machine)
        if before == nil { prune(url.deletingLastPathComponent()) }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoded.write(to: url, options: .atomic)
    }

    /// Removes a session's stamp, once the session has ended.
    public static func remove(_ session: String, on machine: Machine) {
        try? FileManager.default.removeItem(at: file(session, on: machine))
    }

    /// A session's file, its id kept to the characters a file name takes as they are.
    static func file(_ session: String, on machine: Machine) -> URL {
        let name = String(session.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }.map(Character.init))
        return machine.cacheFolder.appending(path: "sessions/\(name.isEmpty ? "_" : name).json")
    }

    static func prune(_ folder: URL) {
        let oldest = Date.now.addingTimeInterval(-Double(keptDays) * 24 * 3600)
        for entry in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        where ((try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .now) < oldest {
            try? FileManager.default.removeItem(at: entry)
        }
    }
}
