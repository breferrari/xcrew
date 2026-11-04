import Foundation

/// What the branch's test runs' coverage says of its changed lines together (docs/findings.md, *The branch's test
/// runs*). A run speaks for a changed file only while the file is unchanged since the run started: then the run compiled
/// the file as it is now, whatever branch the checkout was on, since a checkout, a rebase or an edit gives every file it
/// rewrites a new modification time. A run of no test is left out: its coverage holds nothing run.
struct BranchCoverage: Sendable {
    /// A test run's result bundle, and when it started and finished.
    struct Run: Sendable, Equatable {
        let path: String
        let started: Date
        let finished: Date
    }

    /// What the runs read say together, as `ChangedLineCoverage` words it.
    let sentence: String
    /// When each run that spoke finished, newest first.
    let finished: [Date]

    /// The runs that can speak for any changed file, newest first: started no earlier than the earliest of the changed
    /// files' last changes, as a run that started before every one of them compiled none of them as they are. Nil with
    /// no change to go by, as on a branch that only deletes files.
    static func candidates(_ runs: [Run], lastChanges modified: [Date]) -> [Run]? {
        guard let earliest = modified.min() else { return nil }
        return runs.filter { $0.started >= earliest }.sorted { $0.finished > $1.finished }
    }

    /// When MobileBuildMCP started the run, from its bundle's name: it names the bundle before it builds
    /// (`utils/test-common.js`, `createDefaultResultBundlePath`), while `xcodebuild` makes the folder only in the test
    /// phase, after compiling. Nil for a name it didn't give, which gives the run no start.
    static func started(_ name: String) -> Date? {
        guard let tool = name.firstMatch(of: /^(.+?)_\d{4}-\d{2}-\d{2}T/)?.output.1, let opened = RunLog.openedAt(name, tool: String(tool)) else { return nil }
        return Date(timeIntervalSince1970: Double(opened) / 1000)
    }

    /// Whether a run ran a test, from its summary: one whose tests all were skipped ran none. A summary that can't be read
    /// says nothing either way, so the run's coverage is read.
    static func ranTests(summary: String) -> Bool {
        guard let counts = ResultBundle.counts(summary: summary) else { return true }
        return (counts.passed ?? 0) + (counts.failed ?? 0) > 0
    }

    /// The test runs in this project's MobileBuildMCP workspace: the finished ones, or the newest unfinished one when none
    /// has finished, as `ResultBundle.newest` takes them. A run starts as `started` reads its name, and finishes when
    /// it's last written; one whose name gives no start is left out.
    static func runs(project: Project, home: URL) -> [Run] {
        let mark = ResultBundle.completionMark
        let finished = RunLog.candidates(in: "result-bundles", project: project.root, home: home) { $0.hasSuffix(".xcresult" + mark) }
        let unfinished = { RunLog.newest(RunLog.candidates(in: "result-bundles", project: project.root, home: home) { $0.hasSuffix(".xcresult") }, since: .distantPast).prefix(1) }
        return (finished.isEmpty ? Array(unfinished()) : finished).compactMap { item in
            let bundle = item.path.hasSuffix(mark) ? URL(fileURLWithPath: String(item.path.dropLast(mark.count))) : item
            guard let started = started(bundle.lastPathComponent) else { return nil }
            return Run(path: bundle.path, started: started, finished: EvidencePack.modified(item))
        }
    }

    /// What the branch's runs say of `change`, every run read to its end: nothing when there's no run here or none says
    /// anything, and no run at all when every run started before every changed file's last change. The runs are read side
    /// by side, each in its own lane of the runner's pool, newest first, so the newest runs' commands go ahead. The files
    /// only test targets build are left out of those outside the coverage once, for every run read, after the reading.
    static func read(change: GitChanges.Change, project: Project, machine: Machine) async -> BranchCoverage? {
        let all = runs(project: project, home: machine.home)
        guard !all.isEmpty, let chosen = candidates(all, lastChanges: change.files.compactMap { EvidencePack.modifiedIfKnown(URL(fileURLWithPath: $0)) }) else { return nil }
        guard !chosen.isEmpty else { return BranchCoverage(sentence: "", finished: []) }
        // The targets are read at once, beside the runs.
        let targets = Task { WorkspaceGraph.read(project) }
        let read = await withTaskGroup(of: (coverage: ChangedLineCoverage, finished: Date)?.self) { runs in
            for (lane, run) in chosen.enumerated() {
                runs.addTask {
                    let runner = CommandPool.lane(of: machine.runner, lane)
                    let bundle = ResultBundle(path: run.path, runner: runner)
                    let reading: ChangedLineCoverage? = ranTests(summary: await bundle.summary())
                        ? await ChangedLineCoverage.of(bundle, change: { change }, project: project, using: runner, keepingTestFiles: true)
                        : nil
                    guard let fresh = reading?.fresh(since: run.started, modified: { EvidencePack.modifiedIfKnown(URL(fileURLWithPath: $0)) }) else { return nil }
                    return (coverage: fresh, finished: run.finished)
                }
            }
            var found: [(coverage: ChangedLineCoverage, finished: Date)] = []
            for await one in runs { if let one { found.append(one) } }
            return found
        }
        let kept = Set(ChangedLineCoverage.withoutTestFiles(Array(Set(read.flatMap(\.coverage.outside))).sorted(), in: await targets.value))
        let found = read.sorted { $0.finished > $1.finished }.map { coverage, finished in
            var coverage = coverage
            coverage.outside = coverage.outside.filter(kept.contains)
            return (coverage: coverage, finished: finished)
        }
        return together(found)
    }

    /// What the runs read say together, the runs that spoke named by when they finished.
    static func together(_ found: [(coverage: ChangedLineCoverage, finished: Date)]) -> BranchCoverage? {
        guard let sentence = ChangedLineCoverage.merged(found.map(\.coverage)).sentence else { return nil }
        return BranchCoverage(sentence: sentence, finished: ChangedLineCoverage.speakers(found.map(\.coverage)).map { found[$0].finished })
    }

    /// The evidence block's line: the runs by when they finished, said to be older than the branch's last commit when the
    /// newest is, then what they say.
    func line(lastCommit: Date?) -> String {
        guard !finished.isEmpty else { return "- No test run here speaks for the changed lines: each started before their last change." }
        let runs = finished.count == 1 ? "the test run" : "the test runs"
        let stamps = ResultBundle.joined(finished.map(EvidencePack.stamp), rest: nil)
        let dated = EvidencePack.when(runs, of: stamps, at: finished.max() ?? .distantPast, lastCommit: lastCommit)
        return "- \(dated): \(sentence)"
    }
}
