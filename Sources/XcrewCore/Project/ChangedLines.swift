import Foundation

/// The lines a branch changed since its merge base with the default branch, uncommitted and untracked files included,
/// as `git diff -U0` gives them: a warning in one of them is in code the change touched (docs/findings.md, *Warnings
/// in changed lines*).
enum ChangedLines {
    /// The changed lines of each of `paths` the change holds, by the path as given; an untracked file counts whole.
    /// Nothing when git can't diff the change.
    static func of(_ paths: some Sequence<String>, in change: GitChanges.Change, project: Project, using runner: any CommandRunning) async -> [String: [ClosedRange<Int>]]? {
        let given = Dictionary(grouping: Set(paths), by: ProjectLayout.canonicalPath)
        let untracked = Set(change.untracked)
        let tracked = change.files.filter { given[$0] != nil && !untracked.contains($0) }
        var lines: [String: [ClosedRange<Int>]] = [:]
        if !tracked.isEmpty {
            // Every name as written, and no `a/` or `b/` before it.
            let diff = await runner.run(["git", "-C", project.root.path, "-c", "core.quotePath=false", "diff", "-U0", "--no-color", "--no-renames", "--no-relative", "--no-prefix", change.since, "--"] + tracked, stdin: nil, timeout: .seconds(30))
            guard diff.succeeded else { return nil }
            lines = hunks(diff.stdout, top: change.top)
        }
        for file in untracked where given[file] != nil { lines[file] = [1...Int.max] }
        var found: [String: [ClosedRange<Int>]] = [:]
        for (file, ranges) in lines {
            for path in given[file] ?? [] { found[path] = ranges }
        }
        return found
    }

    /// The new side of each hunk, `@@ -l,s +l,s @@`, by file: a count of 0 adds no line, an omitted count means one.
    /// A hunk's own lines are counted off, since without context one can read like a file's header.
    static func hunks(_ diff: String, top: String) -> [String: [ClosedRange<Int>]] {
        var found: [String: [ClosedRange<Int>]] = [:]
        var file: String?
        var (removed, added) = (0, 0)
        // By byte: a CRLF ending is one Character, which a split on "\n" would pass over.
        for line in diff.utf8.split(separator: UInt8(ascii: "\n")).map({ String(decoding: $0, as: UTF8.self) }) {
            if removed > 0, line.hasPrefix("-") {
                removed -= 1
            } else if added > 0, line.hasPrefix("+") {
                added -= 1
            } else if line.hasPrefix("+++ ") {
                let path = name(line.dropFirst(4))
                file = path == "/dev/null" ? nil : "\(top)/\(path)"
            } else if line.hasPrefix("@@ "), let match = line.firstMatch(of: /^@@ -\d+(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/), let start = Int(match.2) {
                let count = match.3.flatMap { Int($0) } ?? 1
                (removed, added) = (match.1.flatMap { Int($0) } ?? 1, count)
                if let file, count > 0 { found[file, default: []].append(start...(start + count - 1)) }
            }
        }
        return found
    }

    /// A name as a header writes it: ended with a tab when it holds a space, and C-quoted when it holds a quote, a
    /// backslash or a control character (`core.quotePath=false` leaves other bytes as they are).
    static func name(_ written: Substring) -> String {
        let written = written.hasSuffix("\t") ? written.dropLast() : written
        guard written.count > 1, written.hasPrefix("\""), written.hasSuffix("\"") else { return String(written) }
        var bytes: [UInt8] = []
        var rest = Array(written.utf8.dropFirst().dropLast())[...]
        while let byte = rest.popFirst() {
            guard byte == UInt8(ascii: "\\"), let escaped = rest.popFirst() else {
                bytes.append(byte)
                continue
            }
            guard (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(escaped) else {
                bytes.append(escapes[escaped] ?? escaped)
                continue
            }
            var value = Int(escaped - UInt8(ascii: "0"))
            while value < 32, let digit = rest.first, (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(digit) {
                value = value * 8 + Int(digit - UInt8(ascii: "0"))
                rest.removeFirst()
            }
            bytes.append(UInt8(truncatingIfNeeded: value))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The letters git writes after a backslash for a control character.
    static let escapes: [UInt8: UInt8] = [UInt8(ascii: "a"): 7, UInt8(ascii: "b"): 8, UInt8(ascii: "t"): 9, UInt8(ascii: "n"): 10, UInt8(ascii: "v"): 11, UInt8(ascii: "f"): 12, UInt8(ascii: "r"): 13]
}
