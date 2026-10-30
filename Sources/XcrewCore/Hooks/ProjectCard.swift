import Foundation

/// The project card the mod saves after each run and at session start, for `xcrew hook session-start` to print. It used
/// to reach Claude through a `prompt.context` hook, which Claude Code passes over on some plans (docs/findings.md,
/// *Prompt hooks a plugin can't count on*), so its rules are that hook's: one card per folder and branch, dropped once
/// its data is older than the mod keeps its history.
public enum ProjectCard {
    /// One folder's and branch's card: what the mod built, and when its newest data was written, in milliseconds since
    /// 1970 as the mod's clock gives it. No text clears the card.
    public struct Entry: Codable, Sendable, Equatable {
        public var folder: String
        public var branch: String
        public var updated: Double
        public var text: String?

        public init(folder: String, branch: String, updated: Double, text: String?) {
            self.folder = folder
            self.branch = branch
            self.updated = updated
            self.text = text
        }
    }

    struct Saved: Codable {
        var version: Int
        var entries: [Entry]
    }

    static let version = 1
    /// As long as the mod keeps its history (`HISTORY_KEPT_MS` in hooks/mod/timing.ts).
    static let keptDays = 14

    static func file(on machine: Machine) -> URL {
        machine.cacheFolder.appending(path: "cards.json")
    }

    /// Saves one card in place of that folder's and branch's last, dropping the stale ones. A file a newer xcrew wrote
    /// is left as it is. Written whole, through a file beside it renamed over it, so two sessions can't tear it.
    public static func save(_ entry: Entry, on machine: Machine, now: Date = Date()) {
        let file = file(on: machine)
        var saved = Saved(version: version, entries: [])
        if let data = try? Data(contentsOf: file) {
            guard let read = try? JSONDecoder().decode(Saved.self, from: data) else { return write(saved, entry, to: file, now: now) }
            guard read.version <= version else { return }
            saved.entries = read.entries
        }
        write(saved, entry, to: file, now: now)
    }

    private static func write(_ saved: Saved, _ entry: Entry, to file: URL, now: Date) {
        var saved = saved
        let folder = ProjectLayout.canonicalPath(entry.folder)
        saved.entries.removeAll { ($0.folder == folder && $0.branch == entry.branch) || isStale($0, now: now) }
        if entry.text != nil { saved.entries.append(Entry(folder: folder, branch: entry.branch, updated: entry.updated, text: entry.text)) }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(saved).write(to: file, options: .atomic)
    }

    /// The card for this folder and branch, its first line saying how old it is, or nothing when there's none or it's
    /// stale.
    public static func text(folder: String, branch: String, now: Date, on machine: Machine) -> String? {
        guard let data = try? Data(contentsOf: file(on: machine)),
              let saved = try? JSONDecoder().decode(Saved.self, from: data), saved.version <= version,
              let entry = saved.entries.last(where: { $0.folder == ProjectLayout.canonicalPath(folder) && $0.branch == branch }),
              !isStale(entry, now: now), let text = entry.text
        else { return nil }
        let age = "as of the run \(ago(now.timeIntervalSince1970 - entry.updated / 1000))"
        var lines = text.components(separatedBy: "\n")
        if let first = lines.first, first.hasSuffix(":") { lines[0] = "\(first.dropLast()), \(age):" } else { lines.insert("(\(age))", at: 0) }
        return lines.joined(separator: "\n")
    }

    /// The mod's `isStale`: more than the kept days before now.
    static func isStale(_ entry: Entry, now: Date) -> Bool {
        now.timeIntervalSince1970 - entry.updated / 1000 > TimeInterval(keptDays * 24 * 3600)
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
