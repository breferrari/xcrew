import Foundation
import Testing
@testable import XcrewCore

@Suite struct StandardInputTests {
    /// Writes `chunks` to a pipe from a thread of its own, `gap` apart, then closes it after `closeAfter`, or never.
    func pipe(writing chunks: [String], gap: Double, closeAfter: Double?) -> FileHandle {
        let pipe = Pipe()
        let writer = pipe.fileHandleForWriting
        Thread {
            for (index, chunk) in chunks.enumerated() {
                if index > 0 { Thread.sleep(forTimeInterval: gap) }
                try? writer.write(contentsOf: Data(chunk.utf8))
            }
            if let closeAfter {
                Thread.sleep(forTimeInterval: closeAfter)
                try? writer.close()
            }
        }.start()
        return pipe.fileHandleForReading
    }

    /// A caller that never closes stdin, as a script can be: reading stops once nothing more arrives. Read to its end, it
    /// would be complete, its writer closing it after 30 seconds: not timed, since a busy test run's own wait dwarfs this.
    @Test func anInputLeftOpenIsReadUntilItGoesQuiet() async throws {
        let input = await StandardInput.read(pipe(writing: [#"{"cwd":"/project"}"#], gap: 0, closeAfter: 30), idleFor: .milliseconds(500))
        #expect(String(decoding: input.data, as: UTF8.self) == #"{"cwd":"/project"}"#)
        #expect(!input.isComplete, "waited for the caller to close stdin")
    }

    /// A writer still sending is read to its end, however long it takes, as long as it doesn't go quiet.
    @Test func aWriterStillSendingIsNotCutOff() async throws {
        let input = await StandardInput.read(pipe(writing: ["one ", "two ", "three"], gap: 0.6, closeAfter: 0.2), idleFor: .seconds(1))
        #expect(String(decoding: input.data, as: UTF8.self) == "one two three")
        #expect(input.isComplete)
    }

    @Test func aClosedInputIsReadToItsEnd() async throws {
        let input = await StandardInput.read(pipe(writing: [String(repeating: "x", count: 200_000)], gap: 0, closeAfter: 0), idleFor: .seconds(5))
        #expect(input.data.count == 200_000)
        #expect(input.isComplete)
    }

    /// `xcrew hook session-start < event.json`: a file always ends, so it's read at once, not after an idle wait. Timed,
    /// since time is all that tells them apart: a read that waited would take at least the minute's idle wait, and 30
    /// seconds is over twice the longest a busy CI run held an awaited call (13 s; docs/findings.md, *Stopping a program*).
    @Test func aFileIsReadAtOnce() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "xcrew-stdin-\(UUID().uuidString).json")
        try Data(#"{"cwd":"/project"}"#.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let clock = ContinuousClock()
        let started = clock.now
        let input = await StandardInput.read(try FileHandle(forReadingFrom: file), idleFor: .seconds(60))
        #expect(String(decoding: input.data, as: UTF8.self) == #"{"cwd":"/project"}"#)
        #expect(clock.now - started < .seconds(30), "waited on a file for end of file")
    }
}
