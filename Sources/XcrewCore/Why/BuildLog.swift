import Foundation

/// What a build log says that a server's result leaves out.
public enum BuildLog {
    /// Each `error:` the log holds: its message, the `file:line` before it when there is one, and the indented lines under
    /// it. A compiler writes `<file>:<line>[:<column>]: [fatal ]error: <message>`, and the file may hold spaces; a line
    /// without one, such as `xcodebuild: error: …`, takes what follows its last `error: `.
    public static func errors(in log: String) -> [ReportedError] {
        let lines = log.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.indices.compactMap { index in
            let line = lines[index]
            let located = line.firstMatch(of: #/^(.+?):(\d+)(?::\d+)?: (?:fatal )?error: (.*)$/#)
            guard let message = located.map({ $0.3 }) ?? line.ranges(of: "error: ").last.map({ line[$0.upperBound...] }) else { return nil }
            let detail = lines[(index + 1)...].prefix { $0.first == " " || $0.first == "\t" }
                .map { $0.trimmingCharacters(in: .whitespaces) }.prefix { !$0.isEmpty }
            return ReportedError(message: String(message), detail: Array(detail), path: located.map { String($0.1) }, line: located.flatMap { Int($0.2) })
        }
    }

    /// Each `warning:` a compiler wrote with its place, once each: `<file>:<line>[:<column>]: warning: <message>`, the file
    /// perhaps holding spaces, as `errors(in:)` reads an error's.
    static func warnings(in log: String) -> [ToolOutput.Warning] {
        var seen = Set<ToolOutput.Warning>()
        return log.split(separator: "\n").compactMap { line -> ToolOutput.Warning? in
            guard line.contains("warning: "), let located = line.firstMatch(of: #/^(.+?):(\d+)(?::\d+)?: warning: (.*)$/#) else { return nil }
            return ToolOutput.Warning(message: String(located.3), path: String(located.1), line: Int(located.2))
        }.filter { seen.insert($0).inserted }
    }

    /// The log's start, which holds xcodebuild's command line: a clean build's log runs to tens of megabytes.
    static let head = 64 * 1024

    /// The DerivedData folder xcodebuild was given, from its `-derivedDataPath`.
    public static func derivedData(ofLogAt path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let start = String(decoding: (try? handle.read(upToCount: head)) ?? Data(), as: UTF8.self)
        guard let path = start.firstMatch(of: #/-derivedDataPath (?:"([^"]+)"|((?:\\ |[^\s])+))/#) else { return nil }
        return path.1.map(String.init) ?? path.2.map { $0.replacingOccurrences(of: #"\ "#, with: " ") }
    }
}
