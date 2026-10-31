import Foundation

/// A log's lines, read a piece at a time: a clean build's log runs to tens of megabytes.
enum LogLines {
    /// Each line of the file, without its `\n`, read `chunk` bytes at a time; a line split across two reads is joined.
    static func forEach(in file: URL, chunk: Int = 1 << 20, _ body: (Substring) -> Void) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var pending = Data()
        while let read = try handle.read(upToCount: chunk), !read.isEmpty {
            pending.append(read)
            guard let last = pending.lastIndex(of: UInt8(ascii: "\n")) else { continue }
            let text = String(decoding: pending[..<last], as: UTF8.self)
            // Split on the byte, not the Character: a log has no line a grapheme rule would join.
            for line in text.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false) { body(withoutReturn(Substring(line))) }
            pending.removeSubrange(..<pending.index(after: last))
        }
        if !pending.isEmpty { body(withoutReturn(Substring(String(decoding: pending, as: UTF8.self)))) }
    }

    /// A line of a log written with `\r\n` endings, without its `\r`.
    static func withoutReturn(_ line: Substring) -> Substring {
        line.utf8.last == UInt8(ascii: "\r") ? Substring(line.utf8.dropLast()) : line
    }
}
