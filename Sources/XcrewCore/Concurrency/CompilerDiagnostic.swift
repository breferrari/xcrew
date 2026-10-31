import Foundation

/// One diagnostic a compiler wrote to a build log: `<file>:<line>[:<column>]: warning|error: <message> [#Group]`. Since
/// Swift 6.2 a grouped diagnostic ends with its group, a group under another written parent first:
/// `[#RegionIsolation::SendingRisksDataRace]` (docs/findings.md, *Concurrency diagnostics*).
struct CompilerDiagnostic: Sendable, Hashable {
    let path: String
    let line: Int
    let isError: Bool
    /// The message without its group.
    let message: String
    /// Its group and the groups above it, the outermost first; empty when it has none.
    let groups: [String]

    /// The diagnostic a log line holds, or nothing when it holds none.
    static func parse(_ line: Substring) -> CompilerDiagnostic? {
        // By hand rather than with a pattern, and only on a line that can hold one: a clean build's log has hundreds of
        // thousands of lines (docs/findings.md, *Concurrency diagnostics*).
        // The earliest mark is the diagnostic's: its message may hold another.
        guard holds(warningBytes, in: line.utf8) || holds(errorBytes, in: line.utf8),
              let mark = marks.compactMap({ mark in line.range(of: mark.text).map { (range: $0, isError: mark.isError) } }).min(by: { $0.range.lowerBound < $1.range.lowerBound }) else { return nil }
        // `<file>:<line>` or `<file>:<line>:<column>` before it, the file perhaps holding spaces or colons.
        var head = line[..<mark.range.lowerBound]
        guard let lastColon = head.lastIndex(of: ":") else { return nil }
        var number = Int(head[head.index(after: lastColon)...])
        head = head[..<lastColon]
        if let previous = head.lastIndex(of: ":"), let earlier = Int(head[head.index(after: previous)...]) {
            number = earlier
            head = head[..<previous]
        }
        guard let number, !head.isEmpty else { return nil }
        var message = line[mark.range.upperBound...]
        var groups: [String] = []
        if message.hasSuffix("]"), let open = message.range(of: " [#", options: .backwards) {
            groups = message[open.upperBound..<message.index(before: message.endIndex)].split(separator: "::").map(String.init)
            message = message[..<open.lowerBound]
        }
        return CompilerDiagnostic(path: String(head), line: number, isError: mark.isError, message: String(message), groups: groups)
    }

    static let warningBytes = Array("warning: ".utf8), errorBytes = Array("error: ".utf8)

    /// Whether the bytes hold `needle`, compared byte by byte: `String.contains` walks grapheme boundaries, the cost of
    /// reading a log, and neither needle repeats its own start.
    static func holds(_ needle: [UInt8], in bytes: Substring.UTF8View) -> Bool {
        end(of: needle, in: bytes) != nil
    }

    /// Where the bytes' first `needle` ends, compared byte by byte as `holds` does.
    static func end(of needle: [UInt8], in bytes: Substring.UTF8View) -> Substring.UTF8View.Index? {
        var matched = 0
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            index = bytes.index(after: index)
            if byte == needle[matched] {
                matched += 1
                if matched == needle.count { return index }
            } else {
                matched = byte == needle[0] ? 1 : 0
            }
        }
        return nil
    }

    /// What follows a diagnostic's place, as a compiler writes it.
    static let marks: [(text: String, isError: Bool)] = [(": warning: ", false), (": error: ", true), (": fatal error: ", true)]
}
