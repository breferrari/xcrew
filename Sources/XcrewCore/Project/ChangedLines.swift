import Foundation

/// The lines a branch changed since its merge base with the default branch, uncommitted and untracked files included,
/// as `git diff -U0` gives them: a warning in one of them is in code the change touched (docs/findings.md, *Warnings
/// in changed lines*).
enum ChangedLines {
    /// The changed lines of each of `paths` the branch changed, by the path as given; an untracked file counts whole.
    /// Nothing when git can't say what changed.
    static func of(_ paths: some Sequence<String>, in project: Project, using runner: any CommandRunning) async -> [String: [ClosedRange<Int>]]? {
        guard case let .success(change) = await GitChanges.since(nil, in: project, using: runner) else { return nil }
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
        for line in diff.split(whereSeparator: \.isNewline) {
            if removed > 0, line.hasPrefix("-") {
                removed -= 1
            } else if added > 0, line.hasPrefix("+") {
                added -= 1
            } else if line.hasPrefix("+++ ") {
                let path = line.dropFirst(4)
                file = path == "/dev/null" ? nil : "\(top)/\(path)"
            } else if line.hasPrefix("@@ "), let match = line.firstMatch(of: /^@@ -\d+(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/), let start = Int(match.2) {
                let count = match.3.flatMap { Int($0) } ?? 1
                (removed, added) = (match.1.flatMap { Int($0) } ?? 1, count)
                if let file, count > 0 { found[file, default: []].append(start...(start + count - 1)) }
            }
        }
        return found
    }
}
