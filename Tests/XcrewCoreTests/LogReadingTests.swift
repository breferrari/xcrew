import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// A log read on from where the last reading stopped: what was read before is never read again.
@Suite struct LogReadingTests {
    static let start = "Test Suite 'All tests' started at 2026-10-31 04:19:12.301.\n"
    static func passed(_ test: String) -> String { "Test Case '-[AppTests \(test)]' passed (0.101 seconds).\n" }

    func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    /// The bytes read before are changed under the reading: only what was appended since counts.
    @Test func aReadingReadsOnlyWhatWasAppended() throws {
        let project = Project.temporary()
        project.write(Self.start + Self.passed("testOne"), to: "test_sim_1.log")
        let log = project.root.appending(path: "test_sim_1.log")
        let first = try #require(LogReading.reading(log, after: nil))
        #expect(first.phase(expectedTests: nil) == "testing · 1 done")
        project.write(String(repeating: "x", count: (Self.start + Self.passed("testOne")).utf8.count - 1) + "\n", to: "test_sim_1.log")
        try append(Self.passed("testTwo"), to: log)
        #expect(LogReading.reading(log, after: first)?.phase(expectedTests: nil) == "testing · 2 done")
    }

    /// A line still being written counts in this reading's phase, and is read again whole by the next.
    @Test func aLineStillBeingWrittenCountsAndIsReadAgain() throws {
        let project = Project.temporary()
        project.write(Self.start + "Test Case '-[AppTests testOne]' passed (0.1", to: "test_sim_1.log")
        let log = project.root.appending(path: "test_sim_1.log")
        let first = try #require(LogReading.reading(log, after: nil))
        #expect(first.phase(expectedTests: 2) == "testing 1 of 2")
        try append("01 seconds).\n" + Self.passed("testTwo"), to: log)
        #expect(LogReading.reading(log, after: first)?.phase(expectedTests: 2) == "testing 2 of 2")
    }

    /// A log shorter than what was read is another log: it's read from its start.
    @Test func aLogShorterThanItsReadingIsReadAfresh() throws {
        let project = Project.temporary()
        project.write(Self.start + Self.passed("testOne") + Self.passed("testTwo"), to: "test_sim_1.log")
        let log = project.root.appending(path: "test_sim_1.log")
        let first = try #require(LogReading.reading(log, after: nil))
        project.write("SwiftCompile normal arm64 /w/A.swift (in target 'Payments' from project 'App')\n", to: "test_sim_1.log")
        #expect(LogReading.reading(log, after: first)?.phase(expectedTests: nil) == "compiling Payments")
    }

    /// Each captured log, written in pieces of several sizes as a run writes it: read on piece by piece, its phase is the
    /// one reading all that's written at once gives, at every piece.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"), arguments: [4_093, 65_537])
    func eachCapturedLogReadInPiecesHasTheWholeLogsPhase(piece: Int) throws {
        let raw = Testbed.root.appending(path: "captures/raw")
        let logs = try FileManager.default.contentsOfDirectory(at: raw, includingPropertiesForKeys: nil).filter { $0.pathExtension == "log" }
            + [Testbed.root.appending(path: "captures/concurrency/build_sim.log")]
        #expect(logs.count > 10)
        for source in logs {
            let data = try Data(contentsOf: source)
            let project = Project.temporary()
            project.write("", to: "run.log")
            let log = project.root.appending(path: "run.log")
            var reading: LogReading?
            var end = 0
            while end < data.count {
                let next = min(end + piece, data.count)
                let handle = try FileHandle(forWritingTo: log)
                try handle.seekToEnd()
                try handle.write(contentsOf: data[end..<next])
                try handle.close()
                end = next
                reading = LogReading.reading(log, after: reading)
                for expected in [nil, 4] {
                    #expect(reading?.phase(expectedTests: expected) == RunLog.phase(in: data[..<end], expectedTests: expected), "\(source.lastPathComponent) at \(end)")
                }
            }
        }
    }
}
