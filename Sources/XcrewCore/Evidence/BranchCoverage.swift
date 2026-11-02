import Foundation
import Synchronization

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
    /// When each run read finished, newest first.
    let finished: [Date]
    /// How many runs that could have spoken weren't read before `budget` passed.
    let leftOut: Int

    /// How long reading the runs' coverage may take: the mod gives the whole evidence call 300 s (`EVIDENCE_TIMEOUT_MS`),
    /// and 60 s of it stay for the rest of the call and for a run cut off at the deadline to stop, as `xcresulttool` and
    /// `xccov` each wait up to 15 s before they're stopped (docs/findings.md, *The branch's test runs*).
    static let budget = Duration.seconds(240)

    /// The runs that can speak for any changed file, newest first: started no earlier than the earliest of the changed
    /// files' last changes, as a run that started before every one of them compiled none of them as they are.
    static func candidates(_ runs: [Run], changedFiles modified: [Date]) -> [Run] {
        guard let earliest = modified.min() else { return [] }
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

    /// What the branch's runs say of `change`, within `budget`: nothing when there's no run here or none says anything, and
    /// no run at all when every run started before every changed file's last change.
    static func read(change: GitChanges.Change, project: Project, machine: Machine) async -> BranchCoverage? {
        let all = runs(project: project, home: machine.home)
        guard !all.isEmpty else { return nil }
        let chosen = candidates(all, changedFiles: change.files.compactMap { EvidencePack.modifiedIfKnown(URL(fileURLWithPath: $0)) })
        guard !chosen.isEmpty else { return BranchCoverage(sentence: "", finished: [], leftOut: 0) }
        let gathered = Gathered()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for run in chosen {
                    guard !Task.isCancelled else { return }
                    let bundle = ResultBundle(path: run.path, runner: machine.runner)
                    let tested = ranTests(summary: await bundle.summary())
                    let coverage = tested ? await ChangedLineCoverage.of(bundle, change: { change }, project: project, using: machine.runner) : nil
                    guard !Task.isCancelled else { return }
                    gathered.reached.withLock { $0 += 1 }
                    // Each file's date is asked of the file system by the path the coverage spells, which resolves either spelling.
                    if let coverage { gathered.read.withLock { $0.append((coverage.fresh(since: run.started) { EvidencePack.modifiedIfKnown(URL(fileURLWithPath: $0)) }, run.finished)) } }
                }
            }
            group.addTask { try? await Task.sleep(for: budget) }
            await group.next()
            group.cancelAll()
        }
        let found = gathered.read.withLock { $0 }
        let leftOut = chosen.count - gathered.reached.withLock { $0 }
        guard !found.isEmpty else { return leftOut > 0 ? BranchCoverage(sentence: "", finished: [], leftOut: leftOut) : nil }
        guard let sentence = ChangedLineCoverage.merged(found.map(\.coverage)).sentence else { return nil }
        let spoke = found.filter { !$0.coverage.lines.isEmpty }.map(\.finished)
        return BranchCoverage(sentence: sentence, finished: spoke.isEmpty ? [found[0].finished] : spoke, leftOut: leftOut)
    }

    /// What the reading has gathered when the budget passes: the runs read, and how many were reached.
    private final class Gathered: Sendable {
        let read = Mutex<[(coverage: ChangedLineCoverage, finished: Date)]>([])
        let reached = Mutex(0)
    }

    /// The evidence block's line: the runs by when they finished, said to be older than the branch's last commit when the
    /// newest is, then what they say, and the runs left out past the time allowed.
    func line(lastCommit: Date?) -> String {
        guard !finished.isEmpty else {
            return leftOut > 0 ? "- No test run was read in the time allowed: \(leftOut == 1 ? "1 run is" : "\(leftOut) runs are") left out." : "- No test run here speaks for the changed lines: each started before their last change."
        }
        let runs = finished.count == 1 ? "the test run" : "the test runs"
        let stamps = ResultBundle.joined(finished.map(EvidencePack.stamp))
        let dated = EvidencePack.when(runs, of: stamps, at: finished.max() ?? .distantPast, lastCommit: lastCommit)
        let leftOut = leftOut == 0 ? "" : " \(leftOut == 1 ? "1 earlier run" : "\(leftOut) earlier runs") past the time allowed \(leftOut == 1 ? "isn't" : "aren't") counted."
        return "- \(dated): \(sentence)\(leftOut)"
    }
}
