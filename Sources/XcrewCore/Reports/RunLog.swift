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

    /// The log of the MobileBuildMCP run that started at `since`: the newest `<tool>_…log` written
    /// since then, in this project's workspace folder (`<project folder name>-<hash>`).
    public static func find(tool: String, since: Date, project: URL, home: URL) -> URL? {
        let workspaces = home.appending(path: "Library/Developer/MobileBuildMCP/workspaces")
        let prefix = project.lastPathComponent + "-"
        let manager = FileManager.default
        let folders = ((try? manager.contentsOfDirectory(atPath: workspaces.path)) ?? []).filter { $0.hasPrefix(prefix) }
        var newest: (url: URL, modified: Date)?
        for folder in folders {
            let logs = workspaces.appending(path: folder).appending(path: "logs")
            for name in (try? manager.contentsOfDirectory(atPath: logs.path)) ?? [] where name.hasPrefix("\(tool)_") && !name.contains("parser-debug") {
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
