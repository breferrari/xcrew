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

    /// A session's stamp: each writer's field from its own file, else from the one file an older xcrew kept for both.
    public static func read(_ session: String, on machine: Machine) -> SessionStamp? {
        let folder = self.folder(session, on: machine)
        let written = { (field: Field) in try? String(contentsOf: folder.appending(path: field.rawValue), encoding: .utf8) }
        let older = (try? Data(contentsOf: legacyFile(session, on: machine))).flatMap { try? JSONDecoder().decode(SessionStamp.self, from: $0) }
        let stamp = SessionStamp(briefing: written(.briefing) ?? older?.briefing, mod: written(.mod) ?? older?.mod)
        return stamp == SessionStamp() ? nil : stamp
    }

    /// What each writer reports: the start hook its briefing's version, the mod its own.
    public enum Field: String, Sendable {
        case briefing, mod
    }

    /// Records one writer's `field` for a session, in a file of its own that no other writer touches, so two writing at
    /// once, as the start hook and the mod's first doctor read do, each keep theirs. A session's first record removes the
    /// stamps left too long.
    public static func record(_ session: String, on machine: Machine, _ field: Field, version: String) {
        let folder = self.folder(session, on: machine)
        let file = folder.appending(path: field.rawValue)
        guard (try? String(contentsOf: file, encoding: .utf8)) != version else { return }
        if !FileManager.default.fileExists(atPath: folder.path) { prune(folder.deletingLastPathComponent(), now: machine.now()) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data(version.utf8).write(to: file, options: .atomic)
    }

    /// Removes a session's stamp, once the session has ended.
    public static func remove(_ session: String, on machine: Machine) {
        try? FileManager.default.removeItem(at: folder(session, on: machine))
        try? FileManager.default.removeItem(at: legacyFile(session, on: machine))
    }

    /// A session's folder, its id kept to the characters a file name takes as they are.
    static func folder(_ session: String, on machine: Machine) -> URL {
        machine.cacheFolder.appending(path: "sessions/\(fileName(session))")
    }

    /// The one file an older xcrew kept a session's stamp in.
    static func legacyFile(_ session: String, on machine: Machine) -> URL {
        machine.cacheFolder.appending(path: "sessions/\(fileName(session)).json")
    }

    static func fileName(_ session: String) -> String {
        let name = String(session.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }.map(Character.init))
        return name.isEmpty ? "_" : name
    }

    static func prune(_ folder: URL, now: Date) {
        AgedEntries.removing(olderThan: Double(keptDays) * 24 * 3600, in: folder, now: now)
    }
}
