import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// A log read on from where the last reading stopped: what was read before is never read again.
@Suite struct LogReadingTests {
    static let start = "Test Suite 'All tests' started at 2026-10-31 04:19:12.301.\n"
    static func passed(_ test: String) -> String { "Test Case '-[AppTests \(test)]' passed (0.101 seconds).\n" }

    /// Writes over the file's first bytes in place, as no log is written: a reading that read them again would see it.
    static func overwrite(_ url: URL, bytes: Int) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.write(contentsOf: Data((String(repeating: "x", count: bytes - 1) + "\n").utf8))
    }

    func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    /// The scheme the log's invocation names and its latest verdict are kept with the reading, so a tick reads neither
    /// again from the log: the invocation's next line may come in a later read.
    @Test func aReadingKeepsTheSchemeAndTheLatestVerdict() throws {
        let project = Project.temporary()
        project.write("Command line invocation:\n", to: "test_sim_1.log")
        let log = project.root.appending(path: "test_sim_1.log")
        let first = try #require(LogReading.reading(log, after: nil))
        #expect(first.scheme == nil)
        try append("    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -scheme App -destination id=0000\n\n** TEST BUILD SUCCEEDED **\n" + Self.start + Self.passed("testOne"), to: log)
        let second = try #require(LogReading.reading(log, after: first))
        #expect(second.scheme == "App")
        #expect(second.verdict == "** TEST BUILD SUCCEEDED **")
        try append("** TEST EXECUTE SUCCEEDED **\n", to: log)
        #expect(LogReading.reading(log, after: second)?.verdict == "** TEST EXECUTE SUCCEEDED **")
    }

    /// A test's name is kept as its 64-bit FNV-1a hash, the published test vector's for "a".
    @Test func aTestsNameIsKeptAsItsFNV1aHash() {
        #expect(TestProgress.key("a") == 0xaf63_dc4c_8601_ec8c)
    }

    /// The invocation's heading may be the last of the first 64 lines: the line after it still names the scheme.
    @Test func anInvocationOnTheSixtyFifthLineIsRead() throws {
        let project = Project.temporary()
        project.write(String(repeating: "note\n", count: 63) + "Command line invocation:\n    xcodebuild test -scheme App\n", to: "test_sim_1.log")
        #expect(LogReading.reading(project.root.appending(path: "test_sim_1.log"), after: nil)?.scheme == "App")
    }

    /// A verdict still being written, its line unended, or written indented, is the run's verdict.
    @Test func aVerdictUnendedOrIndentedIsRead() throws {
        let project = Project.temporary()
        project.write(Self.start + "** TEST EXECUTE SUCCEEDED **", to: "test_sim_1.log")
        #expect(LogReading.reading(project.root.appending(path: "test_sim_1.log"), after: nil)?.verdict == "** TEST EXECUTE SUCCEEDED **")
        project.write(Self.start + "  ** BUILD FAILED **\n", to: "build_sim_1.log")
        #expect(LogReading.reading(project.root.appending(path: "build_sim_1.log"), after: nil)?.verdict == "** BUILD FAILED **")
    }

    /// A kept reading holds no test's name: its size, read and written each tick, grows by a number a test, not a name.
    @Test func aKeptReadingHoldsNoTestsName() throws {
        let project = Project.temporary()
        project.write(Self.start + (0..<50).map { Self.passed("testSomethingWithAFairlyDescriptiveName\($0)") }.joined(), to: "test_sim_1.log")
        let reading = try #require(LogReading.reading(project.root.appending(path: "test_sim_1.log"), after: nil))
        let kept = String(decoding: try JSONEncoder().encode(reading), as: UTF8.self)
        #expect(!kept.contains("testSomethingWithAFairlyDescriptiveName"))
    }

    /// The bytes read before are changed under the reading: only what was appended since counts.
    @Test func aReadingReadsOnlyWhatWasAppended() throws {
        let project = Project.temporary()
        project.write(Self.start + Self.passed("testOne"), to: "test_sim_1.log")
        let log = project.root.appending(path: "test_sim_1.log")
        let first = try #require(LogReading.reading(log, after: nil))
        #expect(first.phase(expectedTests: nil) == "testing · 1 done")
        try Self.overwrite(log, bytes: (Self.start + Self.passed("testOne")).utf8.count)
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

    /// Another file at the log's path, however long, is another log: it's read from its start.
    @Test func anotherFileAtTheLogsPathIsReadAfresh() throws {
        let project = Project.temporary()
        project.write(Self.start + Self.passed("testOne"), to: "test_sim_1.log")
        let log = project.root.appending(path: "test_sim_1.log")
        let first = try #require(LogReading.reading(log, after: nil))
        let other = project.root.appending(path: "other.log")
        try Data(("SwiftCompile normal arm64 /w/A.swift (in target 'Payments' from project 'App')\n" + String(repeating: "x", count: 200) + "\n").utf8).write(to: other)
        try FileManager.default.removeItem(at: log)
        try FileManager.default.moveItem(at: other, to: log)
        #expect(LogReading.reading(log, after: first)?.phase(expectedTests: nil) == "compiling Payments")
    }

    /// Two readers of one log share its kept reading, the band's and another checkout's line: each going on from what
    /// the other kept, or from an older reading a slower one saved last, reads as one reader alone.
    @Test func readersSharingAKeptReadingReadAsOne() throws {
        let project = Project.temporary()
        project.write(Self.start, to: "test_sim_1.log")
        let log = project.root.appending(path: "test_sim_1.log"), kept = project.root.appending(path: "phases")
        var phases: [String?] = []
        for index in 1...6 {
            try append(Self.passed("test\(index)"), to: log)
            // The fourth read's reader is the slower: it saves the reading it began from after the other's.
            let entry = index == 4 ? try FileManager.default.contentsOfDirectory(at: kept, includingPropertiesForKeys: nil).first : nil
            let older = try entry.map { try Data(contentsOf: $0) }
            phases.append(RunLog.phase(ofLogAt: log, expectedTests: index.isMultiple(of: 2) ? 6 : nil, keptIn: kept))
            if let entry, let older { try older.write(to: entry) }
        }
        #expect(phases == ["testing · 1 done", "testing 2 of 6", "testing · 3 done", "testing 4 of 6", "testing · 5 done", "testing 6 of 6"])
    }

    /// A reading kept for a log nobody has read for a day goes when another log's is first kept.
    @Test func readingsUnreadForADayGo() throws {
        let project = Project.temporary()
        let kept = project.root.appending(path: "phases")
        try FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
        let stale = kept.appending(path: "0000.json"), recent = kept.appending(path: "1111.json")
        for (file, hours) in [(stale, 25.0), (recent, 23.0)] {
            try Data("{}".utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -hours * 3_600)], ofItemAtPath: file.path)
        }
        project.write(Self.start, to: "test_sim_1.log")
        _ = RunLog.phase(ofLogAt: project.root.appending(path: "test_sim_1.log"), expectedTests: nil, keptIn: kept)
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
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
