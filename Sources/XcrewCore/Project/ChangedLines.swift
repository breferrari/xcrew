import Foundation

/// The lines a branch changed since its merge base with the default branch, uncommitted and untracked files included,
/// as `git diff -U0` gives them: a warning in one of them is in code the change touched (docs/findings.md, *Warnings
/// in changed lines*).
public enum ChangedLines {
    /// Each changed file's lines, by its path as the file system spells it; an untracked file counts whole. Nothing
    /// when git can't say what changed.
    public static func of(_ project: Project, using runner: any CommandRunning) async -> [String: [ClosedRange<Int>]]? {
        guard case let .success(change) = await GitChanges.since(nil, in: project, using: runner) else { return nil }
        // Every name as written, and no `a/` or `b/` before it.
        let diff = await runner.run(["git", "-C", project.root.path, "-c", "core.quotePath=false", "diff", "-U0", "--no-color", "--no-renames", "--no-relative", "--no-prefix", change.since], stdin: nil, timeout: .seconds(30))
        guard diff.succeeded else { return nil }
        var lines = hunks(diff.stdout, top: change.top)
        for file in change.untracked { lines[file] = [1...Int.max] }
        return lines
    }

    /// The new side of each hunk, `@@ -l,s +l,s @@`, by file: a count of 0 adds no line, an omitted count means one.
    static func hunks(_ diff: String, top: String) -> [String: [ClosedRange<Int>]] {
        var found: [String: [ClosedRange<Int>]] = [:]
        var file: String?
        for line in diff.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("+++ ") {
                let path = line.dropFirst(4)
                file = path == "/dev/null" ? nil : "\(top)/\(path)"
            } else if line.hasPrefix("@@ "), let file, let match = line.firstMatch(of: /^@@ -\S+ \+(\d+)(?:,(\d+))? @@/), let start = Int(match.1) {
                let count = match.2.flatMap { Int($0) } ?? 1
                if count > 0 { found[file, default: []].append(start...(start + count - 1)) }
            }
        }
        return found
    }
}
