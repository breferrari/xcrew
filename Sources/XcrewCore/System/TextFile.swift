import Foundation

/// A text file read from its start, line by line, until a line gives what's sought or the file ends: nothing caps how
/// far it reads, so a line past where it usually is is still found (docs/findings.md, *No budgets*).
enum TextFile {
    /// How much is read at a time: what the reading holds at once, not how far it goes.
    static let piece = 64 * 1024

    /// The first answer `find` gives for a line, handed the line before it too; nil when no line gives one.
    static func firstLine<T>(in url: URL, _ find: (_ line: Substring, _ previous: Substring?) -> T?) -> T? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let newline = UInt8(ascii: "\n")
        var pending = Data()
        var previous: Substring?
        while true {
            let more = (try? handle.read(upToCount: piece)) ?? Data()
            // Only what this piece added is searched, and what's held is moved only past a line it ended, so a line of
            // any length is read once.
            var start = pending.startIndex
            var from = pending.endIndex
            pending.append(more)
            while let end = pending[from...].firstIndex(of: newline) {
                let line = Substring(String(decoding: pending[start..<end], as: UTF8.self))
                if let found = find(line, previous) { return found }
                previous = line
                start = end + 1
                from = start
            }
            if start > pending.startIndex { pending = Data(pending[start...]) }
            guard !more.isEmpty else { break }
        }
        return pending.isEmpty ? nil : find(Substring(String(decoding: pending, as: UTF8.self)), previous)
    }
}
