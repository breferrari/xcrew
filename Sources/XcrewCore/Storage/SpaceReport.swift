import Foundation

/// What `xcrew space` found, part by part: facts, each with the command that would reclaim it when there is one. It never
/// deletes anything itself.
public struct SpaceReport: Sendable, Equatable, Codable {
    public struct Line: Sendable, Equatable, Codable {
        public let text: String
        public var bytes: Int?
        /// The command that would reclaim it, for the person to run; none when no tool reclaims it safely.
        public var command: String?
    }

    public struct Part: Sendable, Equatable, Codable {
        public let title: String
        public var lines: [Line]
        /// One command for the part as a whole.
        public var command: String?
        public var note: String?
    }

    public let parts: [Part]

    public var text: String {
        parts.map { part in
            var lines = [part.title]
            for line in part.lines {
                lines.append("  \(line.text)")
                if let command = line.command { lines.append("      \(command)") }
            }
            if let command = part.command { lines.append("      \(command)") }
            if let note = part.note { lines.append("  \(note)") }
            return lines.joined(separator: "\n") + "\n"
        }.joined(separator: "\n")
    }

    /// `13 B`, `305.5 KB`, `8.3 GB`: decimal units, as Finder counts them.
    static func size(_ bytes: Int) -> String {
        guard bytes >= 1000 else { return "\(bytes) B" }
        var value = Double(bytes)
        var unit = 0
        let units = ["B", "KB", "MB", "GB", "TB"]
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        return value.formatted(.number.precision(.fractionLength(1)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))) + " " + units[unit]
    }

    /// `today`, `1 d ago`, `12 d ago`.
    static func age(of date: Date, now: Date) -> String {
        let days = max(0, Int(now.timeIntervalSince(date) / 86_400))
        return days == 0 ? "today" : "\(days) d ago"
    }

    /// A part whose tool didn't answer.
    static func notRead(_ title: String, by command: String) -> Part {
        Part(title: title, lines: [Line(text: "not read: `\(command)` didn't answer")])
    }
}
