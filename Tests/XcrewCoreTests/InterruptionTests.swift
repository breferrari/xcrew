import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// The CLI ends what it started when it's told to stop: a signal it watches cancels its work, and a cancelled run stops
/// its program with the program's children. SIGUSR1 and SIGUSR2 stand for SIGTERM and SIGINT here, which the test
/// runner keeps.
@Suite struct InterruptionTests {
    @Test func aWatchedSignalCancelsTheWorkAndItsProgramsEnd() async throws {
        let runner = SystemCommandRunner(path: "/usr/bin:/bin")
        let held = try await HeldReader.make()
        defer { held.remove() }
        let sender = Task {
            try await until { held.hasStarted }
            kill(getpid(), SIGUSR2)
        }
        let ended = await Interruption.run(on: [SIGUSR2]) { await runner.run(["/bin/sh", "-c", "(\(held.command)) & wait"], stdin: nil) }
        try await sender.value
        #expect(ended.value == .cancelled)
        #expect(ended.signal == SIGUSR2)
        try await until { await runner.run("/usr/bin/pgrep", "-f", held.path).status == 1 }
    }

    /// Work no signal stopped gives its value and no signal, so the CLI exits with the work's own status. A signal
    /// handled just as the work returns can't be driven from a test.
    @Test func workNoSignalStoppedGivesItsValue() async {
        let ended = await Interruption.run(on: [SIGUSR1]) { 7 }
        #expect(ended.value == 7)
        #expect(ended.signal == nil)
    }
}
