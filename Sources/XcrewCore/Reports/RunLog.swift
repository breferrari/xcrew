import CryptoKit
import Foundation

/// What a MobileBuildMCP run is doing now, read from the xcodebuild output it logs as the run goes.
/// Test results land in batches as the parallel runners flush, so a test count moves in steps.
public enum RunLog {
    /// A short phase for the band, or nil before the first task. `expectedTests` is the last run's total.
    public static func phase(of log: String, expectedTests: Int?) -> String? {
        let testing = log.range(of: "\nTesting started", options: .backwards)?.lowerBound ?? (log.hasPrefix("Testing started") ? log.startIndex : nil)
        if let testing {
            let done = log[testing...].matches(of: #/(?m)^Test case '.*' (?:passed|failed)/#).count
            if let expectedTests, done <= expectedTests { return "testing \(done) of \(expectedTests)" }
            return "testing · \(done) done"
        }
        // No count for a build: xcodebuild starts work on nearly every module early, and prints no line when one is done.
        return buildStep(log)
    }

    /// How much of a log's end holds its latest task line, nearly always.
    static let tailBytes = 64 * 1024

    /// The phase of the log at `url`, reading only what it needs: a clean build's log runs to tens of
    /// megabytes, and the band asks once a second. A test run's count needs only what follows its last
    /// `Testing started`; a build's step needs only the log's end.
    public static func phase(ofLogAt url: URL, expectedTests: Int?) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let marker = Data("Testing started".utf8)
        if let testing = data.range(of: Data("\n".utf8) + marker, options: .backwards)?.lowerBound ?? (data.starts(with: marker) ? data.startIndex : nil) {
            return phase(of: String(decoding: data[testing...], as: UTF8.self), expectedTests: expectedTests)
        }
        let tail = String(decoding: data.suffix(tailBytes), as: UTF8.self)
        return buildStep(tail) ?? (data.count > tailBytes ? lastStep(in: data) : nil)
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
