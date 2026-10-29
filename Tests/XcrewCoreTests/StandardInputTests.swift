import Foundation
import Testing
@testable import XcrewCore

@Suite struct StandardInputTests {
    @Test func anInputLeftOpenIsReadUntilTheLimit() async throws {
        let pipe = Pipe()
        try pipe.fileHandleForWriting.write(contentsOf: Data(#"{"cwd":"/project"}"#.utf8))
        // Stands for a caller that never closes stdin; closed late only so a reader that waits for it can't hang the suite.
        let writer = pipe.fileHandleForWriting
        Task.detached {
            try? await Task.sleep(for: .seconds(5))
            try? writer.close()
        }
        let clock = ContinuousClock()
        let started = clock.now
        let input = await StandardInput.read(pipe.fileHandleForReading, within: .milliseconds(300))
        #expect(String(decoding: input, as: UTF8.self) == #"{"cwd":"/project"}"#)
        #expect(clock.now - started < .seconds(3), "waited for the caller to close stdin")
    }

    @Test func aClosedInputIsReadToItsEnd() async throws {
        let pipe = Pipe()
        let text = String(repeating: "x", count: 200_000)
        let writer = pipe.fileHandleForWriting
        Task.detached {
            try? writer.write(contentsOf: Data(text.utf8))
            try? writer.close()
        }
        let input = await StandardInput.read(pipe.fileHandleForReading, within: .seconds(10))
        #expect(input.count == 200_000)
    }
}
