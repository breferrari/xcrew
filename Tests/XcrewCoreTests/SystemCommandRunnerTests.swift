import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

@Suite struct SystemCommandRunnerTests {
    let runner = SystemCommandRunner(path: "/usr/bin:/bin")

    @Test func passesStandardInputAndCapturesBothStreams() async {
        let result = await runner.run("/bin/sh", "-c", "cat; echo oops >&2; exit 3", stdin: Data("hello".utf8))
        #expect(result == CommandResult(status: 3, stdout: "hello", stderr: "oops\n"))
    }

    @Test func aMissingProgramReadsAsNotFound() async {
        #expect(await runner.run("no-such-program-xcrew").status == 127)
        #expect(runner.which("no-such-program-xcrew") == nil)
        #expect(runner.which("sh") == "/bin/sh")
    }

    /// A run whose task is cancelled stops its program, as its answer is no longer wanted: what stopping guarantees, not
    /// how fast (docs/findings.md, *Timing an awaited call in a test*).
    @Test func aCancelledRunStopsItsProgram() async throws {
        let held = try await HeldReader.make()
        defer { held.remove() }
        let run = Task { await runner.run(["/bin/sh", "-c", held.command], stdin: nil) }
        try await until { held.hasStarted }
        run.cancel()
        #expect(await run.value == .cancelled)
        try await until { await runner.run("/usr/bin/pgrep", "-f", held.path).status == 1 }
    }

    /// A cancelled run stops the program's own children with it, as the doctor's handshake's shell starts the bridge and
    /// a loop: none is left running once the run ends.
    @Test func aCancelledRunStopsTheProgramsChildrenToo() async throws {
        let held = try await HeldReader.make()
        defer { held.remove() }
        let run = Task { await runner.run(["/bin/sh", "-c", "(\(held.command)) & wait"], stdin: nil) }
        try await until { held.hasStarted }
        run.cancel()
        _ = await run.value
        try await until { await runner.run("/usr/bin/pgrep", "-f", held.path).status == 1 }
    }

    /// The shell exits at once, and its background child keeps stdout open: the wait after exit is a moment's grace, so
    /// the child, which runs until a signal ends it, is still running when the run returns.
    @Test func aGrandchildLeftRunningDoesntHoldUpAFinishedProgram() async throws {
        let held = try await HeldReader.make()
        defer { held.remove() }
        let result = await runner.run(["/bin/sh", "-c", "echo ready; (\(held.command)) &"], stdin: nil)
        let stillRunning = await runner.run("/usr/bin/pgrep", "-f", held.path).status == 0
        _ = await runner.run("/usr/bin/pkill", "-f", held.path)
        #expect(result.status == 0)
        #expect(result.stdout == "ready\n")
        #expect(stillRunning, "waited for the grandchild's pipe")
    }

    @Test func largeOutputDoesNotDeadlock() async {
        // More than a pipe buffer holds, on both streams at once.
        let result = await runner.run("/bin/sh", "-c", "head -c 300000 /dev/zero | tr '\\0' a; head -c 300000 /dev/zero | tr '\\0' b >&2")
        #expect(result.stdout.count == 300_000)
        #expect(result.stderr.count == 300_000)
    }
}
