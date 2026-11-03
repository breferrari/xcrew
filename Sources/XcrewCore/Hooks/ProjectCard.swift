import CryptoKit
import Foundation

/// The project card the mod saves after each run and at session start, for `xcrew hook session-start` to print. It used
/// to reach Claude through a `prompt.context` hook, which Claude Code passes over on some plans (docs/findings.md,
/// *Prompt hooks a plugin can't count on*), so its rules are that hook's: one card per folder and branch, dropped once
/// its data is older than the mod keeps its history.
public enum ProjectCard {
    /// One folder's and branch's card: what the mod built, the time of its newest data and of its oldest, in
    /// milliseconds since 1970 as the mod's clock gives them. No text clears the card.
    public struct Entry: Codable, Sendable, Equatable {
        public var version: Int?
        public var folder: String
        public var branch: String
        public var updated: Double
        /// The time of the card's oldest line: once that one is stale the card is, as the mod drops each line by its own
        /// age. Absent, the card's lines are as old as `updated`.
        public var oldest: Double?
        public var text: String?

        public init(folder: String, branch: String, updated: Double, oldest: Double? = nil, text: String?) {
            self.folder = folder
            self.branch = branch
            self.updated = updated
            self.oldest = oldest
            self.text = text
        }
    }

    static let version = 1
    /// As long as the mod keeps its history (`HISTORY_KEPT_MS` in hooks/mod/timing.ts).
    static let keptDays = 14

    static func folder(on machine: Machine) -> URL {
        machine.cacheFolder.appending(path: "cards")
    }

    /// Each folder's and branch's card is a file of its own, so a save replaces only its own: two sessions saving at once
    /// can't lose the other's.
    static func file(folder: String, branch: String, on machine: Machine) -> URL {
        let key = SHA256.hash(data: Data("\(folder)\n\(branch)".utf8)).hex
        return Self.folder(on: machine).appending(path: "\(key.prefix(32)).json")
    }

    /// Saves one card in place of that folder's and branch's last, written whole through a file renamed over it, and
    /// drops the stale cards. A card a newer xcrew wrote is left as it is.
    public static func save(_ entry: Entry, on machine: Machine, now: Date = Date()) {
        let folder = ProjectLayout.canonicalPath(entry.folder)
        let file = file(folder: folder, branch: entry.branch, on: machine)
        if let existing = read(file), (existing.version ?? version) > version { return }
        if entry.text == nil {
            try? FileManager.default.removeItem(at: file)
        } else {
            var saved = entry
            (saved.version, saved.folder) = (version, folder)
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(saved).write(to: file, options: .atomic)
        }
        let others = (try? FileManager.default.contentsOfDirectory(at: Self.folder(on: machine), includingPropertiesForKeys: nil)) ?? []
        for other in others where other != file {
            if let card = read(other), (card.version ?? version) <= version, isStale(card, now: now) { try? FileManager.default.removeItem(at: other) }
        }
    }

    static func read(_ file: URL) -> Entry? {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Entry.self, from: $0) }
    }

    /// The card for this folder and branch, its first line saying how old it is, or nothing when there's none or it's
    /// stale. `folder` is as the file system spells it.
    public static func text(folder: String, branch: String, now: Date, on machine: Machine) -> String? {
        guard let entry = read(file(folder: folder, branch: branch, on: machine)), (entry.version ?? version) <= version,
              entry.folder == folder, entry.branch == branch, !isStale(entry, now: now), let text = entry.text
        else { return nil }
        let age = "as of the run \(ago(now.timeIntervalSince1970 - entry.updated / 1000))"
        var lines = text.components(separatedBy: "\n")
        if let first = lines.first, first.hasSuffix(":") { lines[0] = "\(first.dropLast()), \(age):" } else { lines.insert("(\(age))", at: 0) }
        return lines.joined(separator: "\n")
    }

    /// The mod's `isStale`, for the card's oldest line: more than the kept days before now.
    static func isStale(_ entry: Entry, now: Date) -> Bool {
        now.timeIntervalSince1970 - (entry.oldest ?? entry.updated) / 1000 > TimeInterval(keptDays * 24 * 3600)
    }

    static func ago(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: "just now"
        case ..<3600: "\(Int(seconds / 60)) min ago"
        case ..<(24 * 3600): "\(Int(seconds / 3600)) h ago"
        default: "\(Int(seconds / (24 * 3600))) d ago"
        }
    }

    /// The key the mod's ledger files a branch under: its name, else `commit <sha>`, else nothing outside git.
    public static func branchKey(_ head: GitHead?) -> String {
        switch head {
        case let .branch(name): name
        case let .commit(sha): "commit \(sha)"
        case nil: ""
        }
    }
}
