import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

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


    /// A caller that never closes stdin, as a script can be: reading stops once nothing more arrives in the idle time,
    /// on a clock the test moves, so no wait on real time decides it.
    @Test func anInputLeftOpenIsReadUntilItGoesQuiet() async throws {
        let pipe = Pipe()
        let clock = ManualClock()
        let drain = Drain(pipe.fileHandleForReading)
        let ended = Task { await drain.ended(idleFor: .milliseconds(500), clock: clock) }
        let sent = #"{"cwd":"/project"}"#
        try pipe.fileHandleForWriting.write(contentsOf: Data(sent.utf8))
        try await until { drain.data.count == sent.utf8.count }
        let quiet = Flag()
        Task { _ = await ended.value; quiet.set() }
        while !quiet.isSet {
            try await until { clock.sleepers == 1 || quiet.isSet }
            clock.advance(by: .milliseconds(500))
            await Task.yield()
        }
        #expect(drain.text == #"{"cwd":"/project"}"#)
        #expect(await ended.value == false, "waited for the caller to close stdin")
        try pipe.fileHandleForWriting.close()
    }

    /// A writer still sending is read to its end, however long it takes, as long as it doesn't go quiet: three chunks a
    /// second apart against a one-second limit, each written once the idle check is asleep and arrived before it wakes.
    @Test func aWriterStillSendingIsNotCutOff() async throws {
        let pipe = Pipe()
        let clock = ManualClock()
        let drain = Drain(pipe.fileHandleForReading)
        let ended = Task { await drain.ended(idleFor: .seconds(1), clock: clock) }
        let stopped = Flag()
        Task { _ = await ended.value; stopped.set() }
        var sent = ""
        for chunk in ["one ", "two ", "three"] {
            // The idle check asleep again, or the read ended: a read cut off fails here, on that, not on a wait.
            try await until { clock.sleepers == 1 || stopped.isSet }
            try #require(!stopped.isSet, "cut off after \(sent.utf8.count) bytes")
            try pipe.fileHandleForWriting.write(contentsOf: Data(chunk.utf8))
            sent += chunk
            let expected = sent.utf8.count
            try await until { drain.data.count == expected }
            clock.advance(by: .seconds(1))
        }
        try pipe.fileHandleForWriting.close()
        #expect(await ended.value)
        #expect(drain.text == "one two three")
        #expect(clock.now.offset == .seconds(3))
    }

    @Test func aClosedInputIsReadToItsEnd() async throws {
        let input = await StandardInput.read(pipe(writing: [String(repeating: "x", count: 200_000)], gap: 0, closeAfter: 0), idleFor: .seconds(5))
        #expect(input.data.count == 200_000)
        #expect(input.isComplete)
    }

    /// `xcrew hook session-start < event.json`: a file always ends, so it's read to its end, never cut off by the idle
    /// wait: a read that waited would end as gone quiet, not complete.
    @Test func aFileIsReadToItsEnd() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "xcrew-stdin-\(UUID().uuidString).json")
        try Data(#"{"cwd":"/project"}"#.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let input = await StandardInput.read(try FileHandle(forReadingFrom: file), idleFor: .seconds(60))
        #expect(String(decoding: input.data, as: UTF8.self) == #"{"cwd":"/project"}"#)
        #expect(input.isComplete)
    }
}
