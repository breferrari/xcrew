import Foundation

/// Of the lines a branch changed that can run, those a test run ran and those it didn't, from the run's coverage
/// archive (docs/findings.md, *Changed lines a test run ran*). It speaks for this run alone: a line it didn't run may
/// be run by a test it left out.
struct ChangedLineCoverage: Sendable, Equatable {
    /// A file's changed lines that can run but didn't.
    struct Missed: Sendable, Equatable {
        let path: String
        let lines: [Int]
    }

    /// How many changed lines that can run ran.
    var ran = 0
    /// The changed lines that can run but didn't, by file.
    var notRun: [Missed] = []
    /// Changed files of a kind the coverage holds that it doesn't hold.
    var outside: [String] = []

    /// How many files' line counts are asked of `xccov` at once.
    static let atOnce = 4

    /// The changed-line coverage of a run whose archive holds `covered`; nothing when the change is empty or git can't
    /// diff it.
    static func of(_ covered: [String], in change: GitChanges.Change, bundle: ResultBundle, project: Project, using runner: any CommandRunning) async -> ChangedLineCoverage? {
        guard !change.files.isEmpty else { return nil }
        // Only the archive's files named like a changed file can be one: the rest, often thousands, are never resolved.
        let names = Set(change.files.map { name(of: $0).lowercased() })
        let candidates = covered.filter { names.contains(name(of: $0).lowercased()) }
        guard let changed = await ChangedLines.of(candidates, in: change, project: project, using: runner) else { return nil }
        var counts: [String: [Int: Bool]] = [:]
        await withTaskGroup(of: (String, [Int: Bool]).self) { group in
            for (index, path) in changed.keys.enumerated() {
                if index >= atOnce, let finished = await group.next() { counts[finished.0] = finished.1 }
                group.addTask { (path, lines(await bundle.coverage(of: path))) }
            }
            for await (path, read) in group { counts[path] = read }
        }
        var found = ChangedLineCoverage()
        for (path, ranges) in changed.sorted(by: { $0.key < $1.key }) {
            let changedLines = (counts[path] ?? [:]).filter { line, _ in ranges.contains { $0.contains(line) } }
            found.ran += changedLines.values.count { $0 }
            let missed = changedLines.filter { !$0.value }.keys.sorted()
            if !missed.isEmpty { found.notRun.append(Missed(path: path, lines: missed)) }
        }
        let held = Set(candidates.map(ProjectLayout.canonicalPath))
        let kinds = Set(covered.map(kind))
        found.outside = change.files.filter { file in
            !held.contains(file) && kinds.contains(kind(of: file)) && FileManager.default.fileExists(atPath: file)
        }
        return found
    }

    static func name(of path: String) -> String {
        URL(filePath: path, directoryHint: .notDirectory).lastPathComponent
    }

    static func kind(of path: String) -> String {
        URL(filePath: path, directoryHint: .notDirectory).pathExtension
    }

    /// Each line that can run, and whether it ran, from `xccov view --archive --file <path> --json`:
    /// `{"<path>": [{"line": 3, "isExecutable": true, "executionCount": 1}, …]}`.
    static func lines(_ json: String) -> [Int: Bool] {
        guard let files = ResultBundle.parse(json) as? [String: Any] else { return [:] }
        var lines: [Int: Bool] = [:]
        for case let entries as [[String: Any]] in files.values {
            for entry in entries where entry["isExecutable"] as? Bool == true {
                guard let line = entry["line"] as? Int else { continue }
                lines[line] = (entry["executionCount"] as? Int ?? 0) > 0
            }
        }
        return lines
    }

    /// Line numbers as runs: `6-8`, `10`.
    static func ranges(_ lines: [Int]) -> [String] {
        var runs: [ClosedRange<Int>] = []
        for line in lines.sorted() {
            if let last = runs.last, last.upperBound + 1 == line { runs[runs.count - 1] = last.lowerBound...line } else { runs.append(line...line) }
        }
        return runs.map { $0.count == 1 ? "\($0.lowerBound)" : "\($0.lowerBound)-\($0.upperBound)" }
    }

    /// What Claude reads: how many changed lines ran, those that didn't, a few named, and the changed files the
    /// coverage doesn't hold. Nothing when no changed line can run and every changed file is held.
    var note: String? {
        let total = ran + notRun.reduce(0) { $0 + $1.lines.count }
        var sentences: [String] = []
        if total > 0 {
            let counted = ran == total ? (total == 1 ? "the 1 changed line that can run" : "all \(total) changed lines that can run") : "\(ran) of \(total) changed lines that can run"
            let named = notRun.flatMap { file in Self.ranges(file.lines).map { "\(ToolOutput.basename(file.path)):\($0)" } }
            sentences.append("\(counted) ran in this test run." + (named.isEmpty ? "" : " Not run\(ResultBundle.listed(named))."))
        }
        if !outside.isEmpty {
            let files = outside.count == 1 ? "1 changed file isn't" : "\(outside.count) changed files aren't"
            sentences.append("\(files) in this run's coverage\(ResultBundle.listed(outside.map(ToolOutput.basename))).")
        }
        return sentences.isEmpty ? nil : "xcrew: " + sentences.joined(separator: " ")
    }
}
