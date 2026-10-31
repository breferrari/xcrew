import Foundation
import Testing
@testable import XcrewCore

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

    /// What stopping guarantees, not how fast (docs/findings.md, *Timing an awaited call in a test*): a run with no timeout
    /// would end with the child's own status, and one that didn't stop it would leave it running.
    @Test func aProgramThatOutlivesItsTimeoutIsStopped() async {
        let duration = "30.\(Int.random(in: 100_000...999_999))"
        let result = await runner.run(["/bin/sleep", duration], stdin: nil, timeout: .milliseconds(200))
        #expect(result.status == 124)
        #expect(await runner.run("/usr/bin/pgrep", "-f", "sleep \(duration)").status == 1, "the child is still running")
    }

    /// The shell's background sleep inherits stdout and ignores SIGTERM. `terminate` signals the shell's whole process
    /// group, so only a child that ignores it outlives the stop (docs/findings.md, *Stopping a program*). A run that waited
    /// for the pipe would return only after the sleep ended, so the sleep still running shows it didn't wait.
    @Test func aGrandchildHoldingAPipeDoesntOutlastTheTimeout() async {
        let duration = "30.\(Int.random(in: 100_000...999_999))"
        let result = await runner.run(["/bin/sh", "-c", "(trap '' TERM; exec sleep \(duration)) & wait"], stdin: nil, timeout: .seconds(2))
        let stillRunning = await runner.run("/usr/bin/pgrep", "-f", "sleep \(duration)").status == 0
        _ = await runner.run("/usr/bin/pkill", "-9", "-f", "sleep \(duration)")
        #expect(result.status == 124)
        #expect(stillRunning, "waited for the grandchild's pipe")
    }

    /// The shell exits at once, and its background sleep keeps stdout open. A long time limit: the wait after exit is a
    /// moment's grace, not what's left of the limit, so the sleep is still running when the run returns.
    @Test func aGrandchildLeftRunningDoesntHoldUpAFinishedProgram() async {
        let duration = "30.\(Int.random(in: 100_000...999_999))"
        let result = await runner.run(["/bin/sh", "-c", "echo ready; sleep \(duration) &"], stdin: nil, timeout: .seconds(60))
        let stillRunning = await runner.run("/usr/bin/pgrep", "-f", "sleep \(duration)").status == 0
        _ = await runner.run("/usr/bin/pkill", "-f", "sleep \(duration)")
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
