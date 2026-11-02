import CryptoKit
import Foundation

/// What a MobileBuildMCP run is doing now, read from the xcodebuild output it logs as the run goes.
/// Test results land in batches as the parallel runners flush, so a test count moves in steps.
public enum RunLog {
    /// `phase(in:)` for a log held as text.
    public static func phase(of log: String, expectedTests: Int?) -> String? {
        phase(in: Data(log.utf8), expectedTests: expectedTests)
    }

    /// The phase of the log at `url`. With `readings`, read on from the reading kept in its folder for it, and that reading
    /// kept again, the readings unread for a day before its `now` removed: a clean build's log runs to tens of megabytes,
    /// and the band asks once a second.
    public static func phase(ofLogAt url: URL, expectedTests: Int?, keptIn readings: (folder: URL, now: Date)? = nil) -> String? {
        follow(logAt: url, expectedTests: expectedTests, kind: .build, keptIn: readings)?.phase
    }

    /// What a tick of the band reads of a running log, from its kept reading alone: the phase, the scheme its invocation
    /// names and its latest verdict as `kind`'s outcome, with nothing read again from the log's start or end.
    public static func follow(logAt url: URL, expectedTests: Int?, kind: Report.Kind, keptIn readings: (folder: URL, now: Date)? = nil) -> (phase: String?, scheme: String?, outcome: Bool?)? {
        let file = readings.map { $0.folder.appending(path: SHA256.hash(data: Data(url.path.utf8)).hex + ".json") }
        let before = file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(LogReading.self, from: $0) }
        guard let reading = LogReading.reading(url, after: before) else { return nil }
        if let file, reading != before, let encoded = try? JSONEncoder().encode(reading) {
            if before == nil, let readings { pruneReadings(in: readings.folder, now: readings.now) }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? encoded.write(to: file, options: .atomic)
        }
        return (reading.phase(expectedTests: expectedTests), reading.scheme, reading.verdict.flatMap { outcome(ofVerdict: $0, kind: kind) })
    }

    /// Removes the readings no one has kept for a day before `now`: a run's log is followed only while it runs.
    static func pruneReadings(in folder: URL, now: Date) {
        let oldest = now.addingTimeInterval(-24 * 3600)
        for entry in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        where ((try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now) < oldest {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    /// Where a log's reading is kept between the band's asks, one file a log, with the machine's time now, before which
    /// readings unread for a day are removed.
    public static func readingsKept(on machine: Machine) -> (folder: URL, now: Date) {
        (machine.cacheFolder.appending(path: "phases"), machine.now())
    }

    /// A short phase for the band, or nil before the first task. `expectedTests` is the last run's total. From the
    /// end of the tests' build until testing starts, the phase is testing, with no count (docs/findings.md, *Test progress
    /// in a run's log*). No count for a build: xcodebuild starts work on nearly every module early, and prints no line
    /// when one is done.
    static func phase(in data: Data, expectedTests: Int?) -> String? {
        var reading = LogReading()
        reading.read(data)
        return reading.phase(expectedTests: expectedTests)
    }

    /// How many tests a log's lines say have finished, counted as MobileBuildMCP counts a run's tests (docs/findings.md,
    /// *Test progress in a run's log*). Only shapes a capture or Swift Testing's source holds are read:
    /// - the parallel runner's `Test case '…' passed on 'Clone 1 of …'`;
    /// - a serial run's `Test Case '-[…]' passed|failed|skipped (…)`, but for an expected failure, which XCTest writes as
    ///   passed and MobileBuildMCP leaves out;
    /// - Swift Testing's `✔ Test …() passed after …`, `failed after …`, `skipped` and `was cancelled`, a parameterised test once, but for a
    ///   pass with a known issue, which MobileBuildMCP leaves out, and never a suite's line, a case's or the run's total.
    ///
    /// Plain string checks, not regular expressions: the band reads a whole test run's output once a second.
    static func testsFinished(in log: String) -> Int {
        progress(in: log).finished
    }

    /// The tests a log says have finished, counted as `testsFinished(in:)` counts them, and whether the log has begun
    /// testing again: an XCTest case's result written a second time, as a test plan's next configuration,
    /// `-test-iterations`' next pass and `-retry-tests-on-failure` write it. MobileBuildMCP counts a test once however
    /// often it ran, and the log doesn't say how many more times it will, so no count holds from there. A start of testing
    /// written again is no sign: a relaunch after a crash writes it within one pass. Nor is a Swift Testing name, which
    /// carries no suite, so two suites' tests of one name are two tests; but Swift Testing ends each pass with its run's
    /// total, `Test run with 6 tests …`, so a result after one is a test plan's next configuration's (docs/findings.md,
    /// *Test progress in a run's log*).
    static func progress(in log: String) -> (finished: Int, isRepeated: Bool) {
        var progress = TestProgress()
        for line in log.split(separator: "\n", omittingEmptySubsequences: true) { progress.read(line) }
        return (progress.finished, progress.isRepeated)
    }

    static let serialCase = "Test Case '-["

    /// Swift Testing's total at a run's end, `✘ Test run with 6 tests in 1 suite failed after 5.068 seconds …`.
    static func isSwiftTestingRunTotal(_ line: Substring) -> Bool {
        let words = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        return words.count == 2 && !words[0].isEmpty && words[1].hasPrefix("Test run with ")
    }

    /// Whether a Swift Testing test's result line counts, or nil for any other line. Its name can hold any words, so its
    /// result is the last `passed after`, `failed after` or `was cancelled after` in it, or its end. A cancelled test
    /// counts as skipped, as MobileBuildMCP counts it.
    static func swiftTestingCounts(_ line: Substring) -> Bool? {
        let words = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard words.count == 2, !words[0].isEmpty, words[1].hasPrefix("Test "),
              !words[1].hasPrefix("Test run with "), !words[1].hasPrefix("Test case passing ") else { return nil }
        let test = words[1]
        let passed = test.range(of: " passed after ", options: .backwards)
        let failed = test.range(of: " failed after ", options: .backwards)
        if let passed, failed.map({ $0.lowerBound < passed.lowerBound }) ?? true {
            return !test[passed.upperBound...].contains("known issue")
        }
        if failed != nil { return true }
        if test.hasSuffix(" skipped.") || test.contains(" skipped: \"") { return true }
        if let cancelled = test.range(of: " was cancelled after ", options: .backwards), !test[cancelled.upperBound...].contains(" started.") { return true }
        return nil
    }

    /// The latest task's step: `compiling Utility`, `linking Utility`, or `building Utility`.
    static func buildStep(_ log: String) -> String? {
        for line in log.components(separatedBy: "\n").reversed() {
            guard let task = line.firstMatch(of: #/^(\S+) (.*)\(in target '([^']+)' from project/#) else { continue }
            let kind = task.1, target = task.3
            // The file changes too fast to read and makes the line too long; the module is what says where the build is.
            if kind == "SwiftCompile", task.2.contains(".swift ") { return "compiling \(target)" }
            if kind == "Ld" || kind == "Libtool" { return "linking \(target)" }
            if kind == "CodeSign" { return "signing \(target)" }
            return "building \(target)"
        }
        return nil
    }

    /// MobileBuildMCP's workspace folder for a project root, as its `workspaceKeyForRoot`
    /// (`utils/workspace-identity.js`) names it: the folder's name made safe, then the first 12 hex of the root's
    /// SHA-256 (docs/findings.md, *Which log is the run's*).
    static func workspaceKey(root: String) -> String {
        let name = root.split(separator: "/").last.map(String.init) ?? ""
        // By Unicode scalar, as JavaScript reads the string: a decomposed accent's mark is replaced apart from its letter.
        let safe = name.replacing(/[^A-Za-z0-9._-]+/.matchingSemantics(.unicodeScalar), with: "-")
        let slug = String(safe.replacing(/^[.-]+|[.-]+$/, with: "").prefix(64))
        return "\(slug.isEmpty ? "workspace" : slug)-\(SHA256.hash(data: Data(root.utf8)).hex.prefix(12))"
    }

    /// The run's log for the session running on `machine`: only its own MobileBuildMCP servers' logs count when there
    /// is a session above this process to read them from.
    /// The processes are read only once a log is there to choose among.
    public static func find(tool: String, since: Date, project: URL, machine: Machine) async -> URL? {
        await find(since: since, project: project, machine: machine) { $0.hasPrefix("\(tool)_") }
    }

    /// The log of the run a call started at `since`, in milliseconds since 1970, read once the run has ended: the first
    /// `tool` log opened at or after `since`, by the time MobileBuildMCP names it with (docs/findings.md, *Which log is the
    /// run's*). A later call's log, written since, is another run's. Only this session's servers' logs count, as for
    /// `find`.
    public static func first(tool: String, since: Int, project: URL, machine: Machine) async -> URL? {
        let opened = candidates(project: project, home: machine.home) { openedAt($0, tool: tool).map { $0 >= since } ?? false }
        let mine = opened.isEmpty ? [] : await ofSession(opened, on: machine)
        return mine.compactMap { log in openedAt(log.lastPathComponent, tool: tool).map { (log, $0) } }.min { $0.1 < $1.1 }?.0
    }

    /// When MobileBuildMCP opened a `tool` log, in whole milliseconds since 1970, from its name:
    /// `<tool>_<ISO 8601 time in UTC, ':' and '.' as '-'>_pid…` (`utils/log-naming.js`). Nothing for another tool's log.
    static func openedAt(_ name: String, tool: String) -> Int? {
        guard name.hasPrefix("\(tool)_"),
              let stamp = name.dropFirst(tool.count + 1).prefixMatch(of: /(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})-(\d{3})Z_pid/),
              let second = try? Date.ISO8601FormatStyle().parse("\(stamp.1)T\(stamp.2):\(stamp.3):\(stamp.4)Z"),
              let milliseconds = Int(stamp.5)
        else { return nil }
        return Int(second.timeIntervalSince1970) * 1000 + milliseconds
    }

    /// The newest log MobileBuildMCP wrote for a build or test of this project, whichever tool ran it (`build_sim_…`,
    /// `test_sim_…`, `build_run_sim_…`) and whichever server: an earlier failure's may be a server since restarted, or
    /// another session's.
    public static func newestBuild(project: URL, home: URL) -> URL? {
        find(since: .distantPast, project: project, home: home) { ($0.hasPrefix("build") || $0.hasPrefix("test")) && $0.hasSuffix(".log") }
    }

    static func find(in folder: String = "logs", since: Date, project: URL, machine: Machine, named matches: (String) -> Bool) async -> URL? {
        let written = newest(candidates(in: folder, project: project, home: machine.home, named: matches), since: since)
        return written.isEmpty ? nil : newest(await ofSession(written, on: machine), since: since).first
    }

    /// The items a MobileBuildMCP server of the Claude Code session above this process wrote (`_pid<server>_`): two
    /// sessions in one checkout share the workspace folder. All of them when there's no session, or none of its servers
    /// is recognised. The processes are read only once there are items to choose among.
    static func ofSession(_ items: [URL], on machine: Machine) async -> [URL] {
        let (session, servers) = await ProcessList.load(using: machine.runner).mobileBuildMCPServers(forSessionOf: machine.processID)
        guard session != nil, !servers.isEmpty else { return items }
        return items.filter { item in servers.contains { item.lastPathComponent.contains("_pid\($0.id)_") } }
    }

    /// The log of the MobileBuildMCP run that started at `since`: the newest `<tool>_…log` written since then, in this
    /// project's own workspace folder, and when `servers` is given, written by one of them (`_pid<server>_`): two
    /// sessions in one checkout share the folder. With no servers recognised, every server's logs count. MobileBuildMCP
    /// keys the folder by the root as it found its config, or by its real path, `/private` included, without one, so
    /// both are tried.
    static func find(tool: String, since: Date, project: URL, home: URL, servers: Set<Int32>? = nil) -> URL? {
        find(since: since, project: project, home: home, servers: servers) { $0.hasPrefix("\(tool)_") }
    }

    /// The newest log `matches` names, as `find(tool:…)` picks it; or, with `folder`, the newest item of another of the
    /// workspace's folders, such as `result-bundles`.
    static func find(in folder: String = "logs", since: Date, project: URL, home: URL, servers: Set<Int32>? = nil, named matches: (String) -> Bool) -> URL? {
        let candidates = candidates(in: folder, project: project, home: home, named: matches)
        let servers = servers.flatMap { $0.isEmpty ? nil : $0 }
        let theirs = servers.map { servers in candidates.filter { item in servers.contains { item.lastPathComponent.contains("_pid\($0)_") } } } ?? candidates
        return newest(theirs, since: since).first
    }

    /// The items written at or after `since`, newest first.
    static func newest(_ items: [URL], since: Date) -> [URL] {
        items.compactMap { item in (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate.map { (item, $0) } }
            .filter { $0.1 >= since }.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// The items of the project's own workspace folder that `matches` names.
    static func candidates(in folder: String = "logs", project: URL, home: URL, named matches: (String) -> Bool) -> [URL] {
        let workspaces = home.appending(path: "Library/Developer/MobileBuildMCP/workspaces")
        let roots = [project.path, ProjectLayout.canonical(project)]
        return Set(roots.map(workspaceKey(root:))).flatMap { key in
            let items = workspaces.appending(path: key).appending(path: folder)
            return ((try? FileManager.default.contentsOfDirectory(atPath: items.path)) ?? []).filter { !$0.contains("parser-debug") && matches($0) }.map { items.appending(path: $0) }
        }
    }
}

extension RunLog {
    /// How many of a log's first lines its invocation's heading is looked for in: it heads the log.
    static let invocationWithin = 64

    /// The scheme the run built, from the `Command line invocation:` MobileBuildMCP's log opens with: the line after it is
    /// xcodebuild's command, `-scheme Feature` or `-scheme "My App"`.
    public static func scheme(in log: String) -> String? {
        let lines = log.split(separator: "\n", maxSplits: invocationWithin, omittingEmptySubsequences: false)
        guard let heading = lines.firstIndex(where: { $0.hasPrefix("Command line invocation:") }), heading + 1 < lines.count else { return nil }
        return scheme(inInvocation: lines[heading + 1])
    }

    /// The scheme xcodebuild's command line names: `-scheme Feature` or `-scheme "My App"`.
    static func scheme(inInvocation line: some StringProtocol) -> String? {
        guard let match = String(line).firstMatch(of: /\s-scheme\s+(?:"([^"]+)"|(\S+))/) else { return nil }
        return String(match.1 ?? match.2 ?? "")
    }

    /// The scheme a log names, read from its first part only: the invocation is at its top.
    public static func scheme(ofLogAt url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 65_536) else { return nil }
        return scheme(in: String(decoding: head, as: UTF8.self))
    }

    /// Whether the log's run succeeded, by the last verdict xcodebuild printed; nil before it printed one, and for a verdict
    /// that isn't the run's: a test run's that isn't its tests', or a build and run's success, which is its build's alone
    /// and comes before the app is installed and launched.
    public static func outcome(of log: String, kind: Report.Kind) -> Bool? {
        guard let verdict = log.split(separator: "\n").reversed().lazy.map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { $0.hasPrefix("** ") && $0.hasSuffix(" **") }) else { return nil }
        return outcome(ofVerdict: verdict, kind: kind)
    }

    /// Whether a verdict, `** TEST EXECUTE FAILED **`, says `kind`'s run succeeded, by `outcome(of:kind:)`'s rule.
    static func outcome(ofVerdict verdict: String, kind: Report.Kind) -> Bool? {
        if kind == .test, !verdict.hasPrefix("** TEST ") || verdict.hasPrefix("** TEST BUILD ") { return nil }
        if kind == .run { return verdict.hasSuffix(" FAILED **") ? false : nil }
        return verdict.hasSuffix(" SUCCEEDED **") ? true : verdict.hasSuffix(" FAILED **") ? false : nil
    }

    /// How much of a finished log's end holds its verdict and the result bundle it names, with a long list of failing
    /// tests between them.
    static let endBytes = 1024 * 1024

    /// The end of the log at `path`, where a finished run's verdict and result bundle are: a clean build's log runs to
    /// tens of megabytes. Empty when it can't be read.
    public static func end(ofLogAt path: String) -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else { return "" }
        return String(decoding: data.suffix(endBytes), as: UTF8.self)
    }

    /// The result bundle a test run's log names, on the line after xcodebuild's `Test session results`.
    public static func resultBundle(in log: String) -> String? {
        let lines = log.split(separator: "\n", omittingEmptySubsequences: false)
        guard let heading = lines.firstIndex(where: { $0.hasPrefix("Test session results") }), heading + 1 < lines.count else { return nil }
        let path = lines[heading + 1].trimmingCharacters(in: .whitespaces)
        return path.hasSuffix(".xcresult") ? path : nil
    }
}
