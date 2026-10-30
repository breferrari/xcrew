import Foundation

/// Of the lines a branch changed that can run, those a test run ran and those it didn't, from the run's coverage
/// archive (docs/findings.md, *Changed lines a test run ran*). It speaks for this run alone: a line it didn't run may
/// be run by a test it left out.
struct ChangedLineCoverage: Sendable, Equatable {
    /// How many changed lines that can run ran.
    var ran = 0
    /// A file's changed lines that can run but didn't.
    struct Missed: Sendable, Equatable {
        let path: String
        let lines: [Int]
    }

    /// The changed lines that can run but didn't, by file.
    var notRun: [Missed] = []
    /// Changed files of a kind the coverage holds that it doesn't hold.
    var outside: [String] = []

    /// The changed-line coverage of a run that gathered coverage; nothing when git can't diff the change.
    static func of(_ bundle: ResultBundle, in change: GitChanges.Change, project: Project, using runner: any CommandRunning) async -> ChangedLineCoverage? {
        let covered = await bundle.coveredFiles()
        guard !covered.isEmpty, let changed = await ChangedLines.of(covered, in: change, project: project, using: runner) else { return nil }
        var found = ChangedLineCoverage()
        for path in covered.filter({ changed[$0] != nil }).sorted() {
            let ranges = changed[path] ?? []
            let counted = lines(await bundle.coverage(of: path)).filter { line, _ in ranges.contains { $0.contains(line) } }
            found.ran += counted.values.count { $0 }
            let missed = counted.filter { !$0.value }.keys.sorted()
            if !missed.isEmpty { found.notRun.append(Missed(path: path, lines: missed)) }
        }
        let held = Set(ChangedLines.canonical(covered).keys)
        let kinds = Set(covered.map { URL(fileURLWithPath: $0).pathExtension })
        found.outside = change.files.filter { file in
            !held.contains(file) && kinds.contains(URL(fileURLWithPath: file).pathExtension) && FileManager.default.fileExists(atPath: file)
        }
        return found
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
            let lines = total == 1 ? "changed line that can run" : "changed lines that can run"
            if notRun.isEmpty {
                sentences.append("\(total == 1 ? "the 1" : "all \(total)") \(lines) ran in this test run.")
            } else {
                let named = notRun.flatMap { file in Self.ranges(file.lines).map { "\(ToolOutput.basename(file.path)):\($0)" } }
                sentences.append("\(ran) of \(total) \(lines) ran in this test run. Not run\(ResultBundle.listed(named)).")
            }
        }
        if !outside.isEmpty {
            let files = outside.count == 1 ? "1 changed file isn't" : "\(outside.count) changed files aren't"
            sentences.append("\(files) in this run's coverage\(ResultBundle.listed(outside.map(ToolOutput.basename))).")
        }
        guard !sentences.isEmpty else { return nil }
        return "xcrew: " + sentences.joined(separator: " ")
    }
}
