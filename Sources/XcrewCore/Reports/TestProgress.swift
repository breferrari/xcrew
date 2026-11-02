import Foundation

/// The tests a log's lines say have finished, read a line at a time, and whether the log has begun testing again
/// (`RunLog.progress(in:)`).
struct TestProgress: Codable, Equatable, Sendable {
    var finished = 0
    var isRepeated = false
    /// The XCTest cases written as an expected failure, which MobileBuildMCP leaves out of its counts.
    var expected: Set<String> = []
    /// The tests whose result has been written, by name.
    var seen: Set<String> = []
    /// Whether Swift Testing has written its run's total: a result after it is the next configuration's.
    var swiftTestingRunEnded = false

    mutating func read(_ line: Substring) {
        if line.hasPrefix("Test case '") {
            if line.contains("' passed") || line.contains("' failed") {
                finished += 1
                if !seen.insert(String(line.dropFirst("Test case '".count).prefix { $0 != "'" })).inserted { isRepeated = true }
            }
        } else if line.hasPrefix(RunLog.serialCase), let close = line.range(of: "]' ") {
            let verdict = line[close.upperBound...]
            let test = String(line[..<close.lowerBound].dropFirst(RunLog.serialCase.count))
            if verdict.hasPrefix("passed (") || verdict.hasPrefix("failed (") || verdict.hasPrefix("skipped (") {
                if !expected.contains(test) { finished += 1 }
                if !seen.insert(test).inserted { isRepeated = true }
            }
        } else if let open = line.range(of: "Expected failure in -["), let close = line[open.upperBound...].firstIndex(of: "]") {
            expected.insert(String(line[open.upperBound..<close]))
        } else if let counts = RunLog.swiftTestingCounts(line) {
            if counts { finished += 1 }
            if swiftTestingRunEnded { isRepeated = true }
        } else if RunLog.isSwiftTestingRunTotal(line) {
            swiftTestingRunEnded = true
        }
    }
}
