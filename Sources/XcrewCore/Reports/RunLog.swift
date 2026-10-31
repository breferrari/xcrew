import CryptoKit
import Foundation

/// What a MobileBuildMCP run is doing now, read from the xcodebuild output it logs as the run goes.
/// Test results land in batches as the parallel runners flush, so a test count moves in steps.
public enum RunLog {
    /// `phase(in:)` for a log held as text.
    public static func phase(of log: String, expectedTests: Int?) -> String? {
        phase(in: Data(log.utf8), expectedTests: expectedTests)
    }

    /// The phase of the log at `url`, reading only what it needs: a clean build's log runs to tens of
    /// megabytes, and the band asks once a second. A test run's count needs only what follows its start of testing;
    /// a build's step needs only the log's end.
    public static func phase(ofLogAt url: URL, expectedTests: Int?) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return phase(in: data, expectedTests: expectedTests)
    }

    /// How much of a log's end holds its latest task line, nearly always.
    static let tailBytes = 64 * 1024

    /// A short phase for the band, or nil before the first task. `expectedTests` is the last run's total. From the
    /// end of the tests' build until testing starts, the phase is testing, with no count (docs/findings.md, *Test progress
    /// in a run's log*).
    static func phase(in data: Data, expectedTests: Int?) -> String? {
        if let testing = testingStart(in: data) {
            let done = testsFinished(in: String(decoding: data[testing...], as: UTF8.self))
            if let expectedTests, done <= expectedTests { return "testing \(done) of \(expectedTests)" }
            return "testing · \(done) done"
        }
        if data.range(of: Data("\n** TEST BUILD SUCCEEDED **".utf8), options: .backwards) != nil { return "testing" }
        // No count for a build: xcodebuild starts work on nearly every module early, and prints no line when one is done.
        let tail = String(decoding: data.suffix(tailBytes), as: UTF8.self)
        return buildStep(tail) ?? (data.count > tailBytes ? lastStep(in: data) : nil)
    }

    /// Where testing starts in a log: xcodebuild's own first `Test Suite '…'` line for XCTest, or Swift Testing's
    /// `◇ Test run started.`, whichever comes first. MobileBuildMCP writes its `Testing started` only once the tests have
    /// run, so that's the last resort (docs/findings.md, *Test progress in a run's log*).
    static func testingStart(in data: Data) -> Data.Index? {
        func lineStart(_ marker: String, before end: Data.Index? = nil, options: Data.SearchOptions = []) -> Data.Index? {
            let bytes = Data(marker.utf8)
            if data.starts(with: bytes) { return data.startIndex }
            let line = data.range(of: Data("\n".utf8) + bytes, options: options, in: data.startIndex..<(end ?? data.endIndex))
            return line.map { $0.lowerBound + 1 }
        }
        let suite = lineStart("Test Suite '")
        return lineStart("◇ Test run started.", before: suite) ?? suite ?? lineStart("Testing started", options: .backwards)
    }

    /// How many tests a log's lines say have finished, counted as MobileBuildMCP counts a run's tests (docs/findings.md,
    /// *Test progress in a run's log*). Only shapes a capture or Swift Testing's source holds are read:
    /// - the parallel runner's `Test case '…' passed on 'Clone 1 of …'`;
    /// - a serial run's `Test Case '-[…]' passed|failed|skipped (…)`, but for an expected failure, which XCTest writes as
    ///   passed and MobileBuildMCP leaves out;
    /// - Swift Testing's `✔ Test …() passed after …`, `failed after …` and `skipped`, a parameterised test once, but for a
    ///   pass with a known issue, which MobileBuildMCP leaves out, and never a suite's line, a case's or the run's total.
    ///
    /// Plain string checks, not regular expressions: the band reads a whole test run's output once a second.
    static func testsFinished(in log: String) -> Int {
        var count = 0
        var expected: Set<Substring> = []
        for line in log.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("Test case '") {
                if line.contains("' passed") || line.contains("' failed") { count += 1 }
            } else if line.hasPrefix(serialCase), let close = line.range(of: "]' ") {
                let verdict = line[close.upperBound...]
                let finished = verdict.hasPrefix("passed (") || verdict.hasPrefix("failed (") || verdict.hasPrefix("skipped (")
                if finished, !expected.contains(line[line.index(line.startIndex, offsetBy: serialCase.count)..<close.lowerBound]) {
                    count += 1
                }
            } else if let open = line.range(of: "Expected failure in -["), let close = line[open.upperBound...].firstIndex(of: "]") {
                expected.insert(line[open.upperBound..<close])
            } else if let counted = swiftTestingCounts(line) {
                if counted { count += 1 }
            }
        }
        return count
    }

    static let serialCase = "Test Case '-["

    /// Whether a Swift Testing test's result line counts, or nil for any other line. Its name can hold any words, so its
    /// result is the last `passed after` or `failed after` in it.
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
        return test.hasSuffix(" skipped.") || test.contains(" skipped: \"") ? true : nil
    }

    /// The latest task's step in a log whose end holds none, such as a long run of linker warnings:
    /// each earlier `(in target '` is found in the bytes and only its own line is read.
    static func lastStep(in data: Data) -> String? {
        let mark = Data("(in target '".utf8), newline = UInt8(ascii: "\n")
        var searchEnd = data.endIndex
        while let found = data.range(of: mark, options: .backwards, in: data.startIndex..<searchEnd) {
            let start = data[..<found.lowerBound].lastIndex(of: newline).map { $0 + 1 } ?? data.startIndex
            let end = data[found.upperBound...].firstIndex(of: newline) ?? data.endIndex
            if let step = buildStep(String(decoding: data[start..<end], as: UTF8.self)) { return step }
            searchEnd = start
        }
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

    /// The newest log MobileBuildMCP wrote for a build or test of this project, whichever tool ran it (`build_sim_…`,
    /// `test_sim_…`, `build_run_sim_…`) and whichever server: an earlier failure's may be a server since restarted, or
    /// another session's.
    public static func newestBuild(project: URL, home: URL) -> URL? {
        find(since: .distantPast, project: project, home: home) { ($0.hasPrefix("build") || $0.hasPrefix("test")) && $0.hasSuffix(".log") }
    }

    static func find(in folder: String = "logs", since: Date, project: URL, machine: Machine, named matches: (String) -> Bool) async -> URL? {
        guard find(in: folder, since: since, project: project, home: machine.home, named: matches) != nil else { return nil }
        let (session, servers) = await ProcessList.load(using: machine.runner).mobileBuildMCPServers(forSessionOf: machine.processID)
        return find(in: folder, since: since, project: project, home: machine.home, servers: session == nil ? nil : Set(servers.map(\.id)), named: matches)
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
        let workspaces = home.appending(path: "Library/Developer/MobileBuildMCP/workspaces")
        let servers = servers.flatMap { $0.isEmpty ? nil : $0 }
        let roots = [project.path, ProjectLayout.canonical(project)]
        let manager = FileManager.default
        var newest: (url: URL, modified: Date)?
        for key in Set(roots.map(workspaceKey(root:))) {
            let logs = workspaces.appending(path: key).appending(path: folder)
            for name in (try? manager.contentsOfDirectory(atPath: logs.path)) ?? [] where !name.contains("parser-debug") && matches(name) {
                if let servers, !servers.contains(where: { name.contains("_pid\($0)_") }) { continue }
                let url = logs.appending(path: name)
                guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                      modified >= since, modified > (newest?.modified ?? .distantPast)
                else { continue }
                newest = (url, modified)
            }
        }
        return newest?.url
    }
}

extension RunLog {
    /// Whether the log's run succeeded, by the last verdict xcodebuild printed (`** BUILD SUCCEEDED **`,
    /// `** TEST EXECUTE FAILED **`); nil before it printed one, when that verdict is neither, as for a run interrupted,
    /// and for a test run when it isn't its tests' own, as after building for testing.
    public static func outcome(of log: String, kind: Report.Kind) -> Bool? {
        guard let verdict = log.split(separator: "\n").reversed().lazy.map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { $0.hasPrefix("** ") && $0.hasSuffix(" **") }) else { return nil }
        if kind == .test, !verdict.hasPrefix("** TEST ") || verdict.hasPrefix("** TEST BUILD ") { return nil }
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
