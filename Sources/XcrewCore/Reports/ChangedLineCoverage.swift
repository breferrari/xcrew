import Foundation

/// Of the lines a branch changed that can run, those a test run ran and those it didn't, from the run's coverage
/// archive (docs/findings.md, *Changed lines a test run ran*), or of a branch's runs merged. It speaks for the runs it
/// holds alone: a line they didn't run may be run by a test they left out.
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

    /// Each changed file's changed lines that can run, and whether each ran.
    var lines: [String: [Int: Bool]] = [:]
    /// How many changed lines that can run ran.
    var ran: Int { lines.values.reduce(0) { $0 + $1.values.count { $0 } } }
    /// The changed lines that can run but didn't, by file.
    var notRun: [Missed] {
        lines.keys.sorted().compactMap { path in
            let missed = (lines[path] ?? [:]).filter { !$0.value }.keys.sorted()
            return missed.isEmpty ? nil : Missed(path: path, lines: missed)
        }
    }
    /// Changed files of a kind the coverage holds that it doesn't hold.
    var outside: [String] = []
    /// The targets with changed files that the run didn't reach.
    var unreached: [Unreached] = []
    /// How many runs this speaks for: one, or a branch's runs merged.
    var runs = 1
    /// Changed files a run covered but that changed since it started, which it can't speak for.
    var stale: [String] = []

    /// The changed-line coverage of a run whose report names `covered`: only its files named like a changed file are
    /// resolved, since an app's archive can list thousands. Nothing when the change is empty, or when git can't diff it
    /// or xccov can't give a file's counts, which would make a count up.
    /// With the run's `targets`, a test bundle's files are left out, and a target the run didn't reach is said once
    /// rather than its changed lines one by one; a file every target holding it leaves out is left out. Only files named
    /// like a changed one are resolved, since an app's coverage can list thousands.
    /// With `keepingTestFiles`, the changed files outside the coverage include those only test targets build, for a
    /// caller that leaves them out once, across many runs. Every file's counts are asked at once: the runner's pool decides how many `xccov`s
    /// run together.
    static func of(_ covered: [String], in change: GitChanges.Change, targets: [CoverageTarget], bundle: ResultBundle, project: Project, using runner: any CommandRunning, keepingTestFiles: Bool = false) async -> ChangedLineCoverage? {
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
            for (path, _) in changed { group.addTask { (path, lines(await bundle.coverage(of: path))) } }
            for await (path, read) in group { counts[path] = read }
        }
        var found = ChangedLineCoverage()
        for (path, ranges) in changed {
            guard case let .some(.some(read)) = counts[path] else { return nil }
            let changedLines = read.filter { line, _ in ranges.contains { $0.contains(line) } }
            found.lines[path] = changedLines
        }
        let changedFiles = Set(change.files)
        let unreachedFiles = holding.filter { changedFiles.contains($0.key) && $0.value.allSatisfy(\.isUnreached) }.compactMap { $0.value.first?.module }
        let unreached = Dictionary(grouping: unreachedFiles) { $0 }
        found.unreached = unreached.keys.sorted().map { Unreached(target: $0, files: unreached[$0]?.count ?? 0) }
        let held = Set(named.map(\.canonical)).union(leftOut)
        let kinds = Set(covered.map(kind))
        let root = ProjectLayout.canonical(project.root) + "/"
        let outside = change.files.filter { file in
            file.hasPrefix(root) && !held.contains(file) && kinds.contains(kind(of: file)) && !isManifest(file) && FileManager.default.fileExists(atPath: file)
        }
        found.outside = keepingTestFiles ? outside : withoutTestFiles(outside, of: project)
        return found
    }

    /// This run's say on the changed files unchanged since it `started`; a file modified later holds content the run never
    /// compiled, so its lines there would name the wrong ones: it's named stale instead.
    func fresh(since started: Date, modified: (String) -> Date?) -> ChangedLineCoverage {
        var fresh = self
        let unchanged = Set(lines.keys.filter { path in modified(path).map { $0 <= started } ?? false })
        fresh.lines = lines.filter { unchanged.contains($0.key) }
        fresh.stale = (stale + lines.keys.filter { !unchanged.contains($0) }).sorted()
        return fresh
    }

    /// The runs that speak, by index: those holding a changed file, or every one when none does, as when they agree only
    /// on what they don't hold.
    static func speakers(_ runs: [ChangedLineCoverage]) -> [Int] {
        let holding = runs.indices.filter { !runs[$0].lines.isEmpty }
        return holding.isEmpty ? Array(runs.indices) : holding
    }

    /// What a branch's runs say together: a changed line ran when any run ran it; a file is outside the coverage, and a
    /// target unreached, only when it is so in every run, since a run that reached it says what it ran there. Each file
    /// is taken once, as the file system spells it, since runs spell it as their builds were started.
    static func merged(_ runs: [ChangedLineCoverage]) -> ChangedLineCoverage {
        guard let first = runs.first else { return ChangedLineCoverage() }
        var merged = ChangedLineCoverage(runs: max(1, speakers(runs).reduce(0) { $0 + runs[$1].runs }))
        var spelled: [String: String] = [:]
        for run in runs {
            for (path, lines) in run.lines {
                let canonical = ProjectLayout.canonicalPath(path)
                let key = spelled[canonical] ?? path
                spelled[canonical] = key
                merged.lines[key, default: [:]].merge(lines) { $0 || $1 }
            }
        }
        merged.outside = first.outside.filter { file in runs.allSatisfy { $0.outside.contains(file) } }
        merged.unreached = first.unreached.filter { target in runs.allSatisfy { $0.unreached.contains { $0.target == target.target } } }
        var staleSeen = Set<String>()
        merged.stale = runs.flatMap(\.stale).sorted().filter { path in
            let canonical = ProjectLayout.canonicalPath(path)
            return spelled[canonical] == nil && staleSeen.insert(canonical).inserted
        }
        return merged
    }

    /// The files only test targets build, left out: a test target's own files are no code under test, so their being
    /// outside the coverage says nothing. Read from an Xcode project's own targets, as `xcrew graph --owner` reads
    /// them, only when there are files to say anything of and the call isn't cancelled: the reading can't be stopped
    /// once started. A file an exception set may move keeps its place, as does one no target lists and every file of a
    /// project whose targets can't be read, a plain Swift package's among them.
    static func withoutTestFiles(_ files: [String], of project: Project) -> [String] {
        guard !files.isEmpty, !Task.isCancelled else { return files }
        return withoutTestFiles(files, in: WorkspaceGraph.read(project))
    }

    /// `withoutTestFiles(_:of:)` on targets already read.
    static func withoutTestFiles(_ files: [String], in targets: Result<WorkspaceGraph, WorkspaceGraph.Unread>) -> [String] {
        guard case let .success(graph) = targets else { return files }
        return files.filter { file in
            let built = graph.builders(of: file)
            return built.isExcepted || built.targets.isEmpty || !built.targets.allSatisfy { graph.targets[$0]?.isTest == true }
        }
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

    /// What a test run's coverage says of the lines a branch changed: nothing when the run gathered no coverage, or
    /// `xccov` couldn't read it. A bundle that says it holds none asks nothing of `xccov`, whose start
    /// alone takes over half a second; otherwise the change is read while `xccov`'s report, which names every file the
    /// archive holds, is. `keepingTestFiles` is as `of(_:in:targets:bundle:project:using:keepingTestFiles:)` says.
    static func of(_ bundle: ResultBundle, change: @escaping @Sendable () async -> GitChanges.Change?, project: Project, using runner: any CommandRunning, keepingTestFiles: Bool = false) async -> ChangedLineCoverage? {
        guard await bundle.holdsCoverage() != false else { return nil }
        async let listed = change()
        let targets = CoverageTarget.targets(in: await bundle.coverageReport())
        var seen = Set<String>()
        let covered = targets.flatMap { $0.files.map(\.path) }.filter { seen.insert($0).inserted }
        guard !covered.isEmpty, let change = await listed else { return nil }
        return await of(covered, in: change, targets: targets, bundle: bundle, project: project, using: runner, keepingTestFiles: keepingTestFiles)
    }

    /// What Claude reads: the sentence, marked as xcrew's.
    var note: String? { sentence.map { "xcrew: " + $0 } }

    /// How many changed lines ran, those that didn't, a few named, the targets with changed files the runs didn't reach,
    /// the changed files the coverage doesn't hold, and those changed after every run that covered them. Nothing when
    /// none of that has anything to say.
    var sentence: String? {
        let total = ran + notRun.reduce(0) { $0 + $1.lines.count }
        var sentences: [String] = []
        if total > 0 {
            let counted = ran == total ? (total == 1 ? "the 1 changed line that can run" : "all \(total) changed lines that can run") : "\(ran) of \(total) changed lines that can run"
            let named = notRun.flatMap { file in Self.ranges(file.lines).map { "\(ToolOutput.basename(file.path)):\($0)" } }
            sentences.append("\(counted) ran in \(runs == 1 ? "this test run" : "these test runs")." + (named.isEmpty ? "" : " Not run\(ResultBundle.listed(named, rest: nil))."))
        }
        if !unreached.isEmpty {
            let files = unreached.reduce(0) { $0 + $1.files }
            let named = ResultBundle.joined(unreached.map(\.target), or: true, rest: nil)
            let these = runs == 1 ? "test run" : "test runs"
            sentences.append("\(sentences.isEmpty ? (runs == 1 ? "this" : "these") : (runs == 1 ? "This" : "These")) \(these) ran nothing in \(named), where \(files == 1 ? "1 changed file is" : "\(files) changed files are").")
        }
        if !outside.isEmpty {
            let files = outside.count == 1 ? "1 changed file isn't" : "\(outside.count) changed files aren't"
            sentences.append("\(files) in \(runs == 1 ? "this run's" : "these runs'") coverage\(ResultBundle.listed(outside.map(ToolOutput.basename), rest: nil)).")
        }
        if !stale.isEmpty {
            let files = stale.count == 1 ? "1 changed file" : "\(stale.count) changed files"
            sentences.append("\(files) changed after every run that covered \(stale.count == 1 ? "it" : "them")\(ResultBundle.listed(stale.map(ToolOutput.basename), rest: nil)).")
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }
}
