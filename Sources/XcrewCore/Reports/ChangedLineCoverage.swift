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

    /// A target none of whose lines the run ran, as when a filter left its tests out, and how many changed files it has.
    struct Unreached: Sendable, Equatable {
        let target: String
        let files: Int
    }

    /// How many changed lines that can run ran.
    var ran = 0
    /// The changed lines that can run but didn't, by file.
    var notRun: [Missed] = []
    /// Changed files of a kind the coverage holds that it doesn't hold.
    var outside: [String] = []
    /// The targets with changed files that the run didn't reach.
    var unreached: [Unreached] = []

    /// How many files' line counts are asked of `xccov` at once.
    static let atOnce = 4
    /// How long the whole reading may take: it shares the report's time with the failures and the summary, so past this
    /// the note is dropped and the rest of the report stands.
    static let budget = Duration.seconds(45)

    /// `work`'s answer, or nothing once `limit` has passed, when the work is cancelled: a command it runs is stopped.
    static func within(_ limit: Duration, _ work: @escaping @Sendable () async -> ChangedLineCoverage?) async -> ChangedLineCoverage? {
        await withTaskGroup(of: ChangedLineCoverage?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// The changed-line coverage of a run whose archive holds `covered`: only its files named like a changed file are
    /// resolved, since an app's archive can list thousands. Nothing when the change is empty, or when git can't diff it
    /// or xccov can't give a file's counts, which would make a count up.
    /// With the run's `targets`, a test bundle's files are left out, and a target the run didn't reach is said once
    /// rather than its changed lines one by one; a file every target holding it leaves out is left out. Only files named
    /// like a changed one are resolved, since an app's coverage can list thousands.
    static func of(_ covered: [String], in change: GitChanges.Change, targets: [CoverageTarget], bundle: ResultBundle, project: Project, using runner: any CommandRunning) async -> ChangedLineCoverage? {
        guard !change.files.isEmpty else { return nil }
        let names = Set(change.files.map { ToolOutput.basename($0).lowercased() })
        let isNamed = { (path: String) in names.contains(ToolOutput.basename(path).lowercased()) }
        // Each file named like a changed one, by the path the file system spells, with every target that holds it.
        var holding: [String: [CoverageTarget]] = [:]
        for target in targets {
            for file in target.files where isNamed(file.path) { holding[ProjectLayout.canonicalPath(file.path), default: []].append(target) }
        }
        let leftOut = Set(holding.filter { $0.value.allSatisfy { $0.isTests || $0.isUnreached } }.keys)
        let named = covered.filter(isNamed).map { (path: $0, canonical: ProjectLayout.canonicalPath($0)) }
        let candidates = named.filter { !leftOut.contains($0.canonical) }.map(\.path)
        guard let listed = await ChangedLines.of(candidates, in: change, project: project, using: runner) else { return nil }
        let changed = oneSpellingEach(listed)
        var counts: [String: [Int: Bool]?] = [:]
        await withTaskGroup(of: (String, [Int: Bool]?).self) { group in
            for (index, (path, _)) in changed.enumerated() {
                if index >= atOnce, let finished = await group.next() { counts[finished.0] = finished.1 }
                group.addTask { (path, lines(await bundle.coverage(of: path))) }
            }
            for await (path, read) in group { counts[path] = read }
        }
        var found = ChangedLineCoverage()
        for (path, ranges) in changed {
            guard case let .some(.some(read)) = counts[path] else { return nil }
            let changedLines = read.filter { line, _ in ranges.contains { $0.contains(line) } }
            found.ran += changedLines.values.count { $0 }
            let missed = changedLines.filter { !$0.value }.keys.sorted()
            if !missed.isEmpty { found.notRun.append(Missed(path: path, lines: missed)) }
        }
        let changedFiles = Set(change.files)
        let unreachedFiles = holding.filter { changedFiles.contains($0.key) && $0.value.allSatisfy(\.isUnreached) }.compactMap { $0.value.first?.module }
        let unreached = Dictionary(grouping: unreachedFiles) { $0 }
        found.unreached = unreached.keys.sorted().map { Unreached(target: $0, files: unreached[$0]?.count ?? 0) }
        let held = Set(named.map(\.canonical)).union(leftOut)
        let kinds = Set(covered.map(kind))
        let root = ProjectLayout.canonical(project.root) + "/"
        found.outside = change.files.filter { file in
            file.hasPrefix(root) && !held.contains(file) && kinds.contains(kind(of: file)) && !isManifest(file) && FileManager.default.fileExists(atPath: file)
        }
        return found
    }

    /// Each file once, however many spellings the archive lists it under, by the first in order.
    static func oneSpellingEach(_ listed: [String: [ClosedRange<Int>]]) -> [(path: String, ranges: [ClosedRange<Int>])] {
        var seen = Set<String>()
        return listed.sorted { $0.key < $1.key }.filter { seen.insert(ProjectLayout.canonicalPath($0.key)).inserted }.map { ($0.key, $0.value) }
    }

    static func kind(of path: String) -> String {
        URL(filePath: path, directoryHint: .notDirectory).pathExtension
    }

    /// A package's or Tuist's manifest: code the build reads, never code a test runs.
    static func isManifest(_ path: String) -> Bool {
        let url = URL(filePath: path, directoryHint: .notDirectory)
        let name = url.lastPathComponent
        return ProjectLayout.packageMarkers.contains(name) || ProjectLayout.tuistMarkers.contains(name) || url.pathComponents.contains(ProjectLayout.tuistFolder)
            || (ProjectLayout.tuistManifests.contains(name) && ProjectLayout.importsProjectDescription(url))
    }

    /// Each line that can run, and whether it ran, from `xccov view --archive --file <path> --json`:
    /// `{"<path>": [{"line": 3, "isExecutable": true, "executionCount": 1}, …]}`.
    /// Nothing when the answer isn't that shape.
    static func lines(_ json: String) -> [Int: Bool]? {
        guard let files = ResultBundle.parse(json) as? [String: Any] else { return nil }
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

    /// What a test run's coverage says of the lines a branch changed, within `budget`: nothing when the run gathered no
    /// coverage. The change is asked for only once there's coverage to read it against.
    static func of(_ bundle: ResultBundle, change: @escaping @Sendable () async -> GitChanges.Change?, project: Project, using runner: any CommandRunning) async -> ChangedLineCoverage? {
        await within(budget) {
            let covered = await bundle.coveredFiles()
            guard !covered.isEmpty else { return nil }
            async let report = bundle.coverageReport()
            guard let listed = await change() else { return nil }
            return await of(covered, in: listed, targets: CoverageTarget.targets(in: await report), bundle: bundle, project: project, using: runner)
        }
    }

    /// What Claude reads: the sentence, marked as xcrew's.
    var note: String? { sentence.map { "xcrew: " + $0 } }

    /// How many changed lines ran, those that didn't, a few named, the targets with changed files the run didn't reach,
    /// and the changed files the coverage doesn't hold. Nothing when none of that has anything to say.
    var sentence: String? {
        let total = ran + notRun.reduce(0) { $0 + $1.lines.count }
        var sentences: [String] = []
        if total > 0 {
            let counted = ran == total ? (total == 1 ? "the 1 changed line that can run" : "all \(total) changed lines that can run") : "\(ran) of \(total) changed lines that can run"
            let named = notRun.flatMap { file in Self.ranges(file.lines).map { "\(ToolOutput.basename(file.path)):\($0)" } }
            sentences.append("\(counted) ran in this test run." + (named.isEmpty ? "" : " Not run\(ResultBundle.listed(named))."))
        }
        if !unreached.isEmpty {
            let files = unreached.reduce(0) { $0 + $1.files }
            let named = ResultBundle.joined(unreached.map(\.target), or: true)
            sentences.append("\(sentences.isEmpty ? "this" : "This") test run ran nothing in \(named), where \(files == 1 ? "1 changed file is" : "\(files) changed files are").")
        }
        if !outside.isEmpty {
            let files = outside.count == 1 ? "1 changed file isn't" : "\(outside.count) changed files aren't"
            sentences.append("\(files) in this run's coverage\(ResultBundle.listed(outside.map(ToolOutput.basename))).")
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }
}
