import Foundation
import Synchronization
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// One deadline for a call, passed down: each command it starts takes what's left of it, and what it cuts is named.
@Suite struct DeadlineRunnerTests {
    static let start = Date(timeIntervalSince1970: 1_767_225_600)

    /// A command asking 15 s with 4 s left gets 4 s, and one asking 2 s gets its 2 s.
    @Test func aCommandTakesWhatsLeftOfTheDeadline() async {
        let recording = TimingRunner()
        let runner = DeadlineRunner(recording, deadline: .seconds(4), now: { .zero })
        _ = await runner.run(["xcrun", "xccov", "view"], stdin: nil, timeout: .seconds(15))
        _ = await runner.run(["git", "diff"], stdin: nil, timeout: .seconds(2))
        #expect(recording.timeouts == [.seconds(4), .seconds(2)])
        #expect(runner.cut.isEmpty)
    }

    /// Past the deadline a command isn't started: it answers as timed out, and is named as cut.
    @Test func pastTheDeadlineACommandIsntStarted() async {
        let recording = TimingRunner()
        let runner = DeadlineRunner(recording, deadline: .zero, now: { .seconds(1) })
        #expect(await runner.run(["xcrun", "xccov", "view"], stdin: nil, timeout: .seconds(15)) == .timedOut)
        #expect(recording.timeouts.isEmpty)
        #expect(runner.cut == ["xccov"])
    }

    /// A command that timed out once the deadline had passed is named as cut; one that timed out before it, at its own
    /// limit or cancelled, isn't.
    @Test func aCommandTheDeadlineStoppedIsNamed() async {
        let clock = Mutex(Duration.zero)
        let runner = DeadlineRunner(TimingRunner(answer: .timedOut, after: { clock.withLock { $0 += .seconds(2) } }), deadline: .seconds(3), now: { clock.withLock { $0 } })
        _ = await runner.run(["git", "diff"], stdin: nil, timeout: .seconds(2))
        #expect(runner.cut.isEmpty)
        _ = await runner.run(["xcrun", "xcresulttool", "get"], stdin: nil, timeout: .seconds(15))
        #expect(runner.cut == ["xcresulttool"])
        // Cancelled with time still left, its limit shortened or not: the deadline didn't stop it.
        let cancelled = DeadlineRunner(TimingRunner(answer: .timedOut), deadline: .seconds(3), now: { .zero })
        _ = await cancelled.run(["xcrun", "xccov", "view"], stdin: nil, timeout: .seconds(15))
        #expect(cancelled.cut.isEmpty)
    }

    /// A command stopped at its own limit, shorter than what was left, isn't named as cut, though its output held it
    /// until past the deadline.
    @Test func aCommandItsOwnLimitStoppedIsntNamed() async {
        let clock = Mutex(Duration.zero)
        let runner = DeadlineRunner(TimingRunner(answer: .timedOut, after: { clock.withLock { $0 += .seconds(4) } }), deadline: .seconds(3), now: { clock.withLock { $0 } })
        _ = await runner.run(["git", "diff"], stdin: nil, timeout: .seconds(2))
        #expect(runner.cut.isEmpty)
    }

    /// The line on a cut says what each program's answer would have added, the note left out, in one sentence.
    @Test func whatACutLeftOutIsNamedByItsNote() {
        #expect(DeadlineRunner.leftOut(["xccov"]) == "This call's time ran out before xccov answered, so the changed lines' coverage is left out of this result.")
        #expect(DeadlineRunner.leftOut(["xcresulttool", "xccov"], of: "this block", leadIn: "xcrew: ") == "xcrew: this call's time ran out before xcresulttool and xccov answered, so what the run's result bundle adds and the changed lines' coverage are left out of this block.")
        #expect(DeadlineRunner.leftOut(["git", "simctl"]) == "This call's time ran out before git and simctl answered, so what the branch changed and what simctl reads are left out of this result.")
        #expect(DeadlineRunner.leftOut([]) == nil)
    }

    /// What the CLI keeps to answer outlasts the time a stopped command's output is waited for, so a cut command can't
    /// hold the answer past the caller's limit.
    @Test func theTimeKeptToAnswerOutlastsAStoppedCommandsGrace() {
        #expect(DeadlineRunner.answering > SystemCommandRunner.grace)
    }

    /// The wait for a call's deadline follows the machine's clock: past it already, it ends at once; moved past it
    /// meanwhile, it ends then, not when the time left at its start would have run out.
    @Test(.timeLimit(.minutes(1))) func theWaitForTheDeadlineFollowsTheMachinesClock() async {
        let reads = Mutex(0)
        let past = Machine(environment: [:], home: URL(fileURLWithPath: "/nonexistent"), runner: FakeRunner(), monotonic: { .seconds(1) }, deadline: .zero)
        await past.untilDeadline(otherwise: .seconds(3600))
        // The clock reads the start once, then an hour on: a wait that read it only once would sleep the hour.
        let machine = Machine(environment: [:], home: URL(fileURLWithPath: "/nonexistent"), runner: FakeRunner(), monotonic: {
            reads.withLock { reads in
                defer { reads += 1 }
                return reads == 0 ? .zero : .seconds(3600)
            }
        }, deadline: .seconds(3600))
        await machine.untilDeadline(otherwise: .seconds(3600))
    }

    /// A deadline runs on the machine's monotonic clock: the wall clock set back an hour, as an NTP step can, gives no
    /// command more time.
    @Test func theWallClockMovesNoDeadline() async {
        let wall = Mutex(Self.start)
        let recording = TimingRunner(after: { wall.withLock { $0 = $0.addingTimeInterval(-3600) } })
        let machine = Machine(environment: ["XCREW_WITHIN_MS": "10000"], home: URL(fileURLWithPath: "/nonexistent"), runner: recording, now: { wall.withLock { $0 } }, monotonic: { .seconds(5) })
        let timed = machine.answering(by: DeadlineRunner.deadline(for: machine))
        _ = await timed.runner.run(["git", "diff"], stdin: nil, timeout: .seconds(15))
        _ = await timed.runner.run(["git", "log"], stdin: nil, timeout: .seconds(15))
        #expect(recording.timeouts == [.milliseconds(8_500), .milliseconds(8_500)])
    }

    /// The CLI takes its deadline from the time the mod gives it, less what it needs to answer.
    @Test func theCLIsDeadlineIsTheTimeItIsGiven() {
        let machine = Machine(environment: ["XCREW_WITHIN_MS": "10000"], home: URL(fileURLWithPath: "/nonexistent"), runner: FakeRunner(), monotonic: { .seconds(5) })
        #expect(DeadlineRunner.deadline(for: machine) == .milliseconds(13_500))
        let unset = Machine(environment: [:], home: URL(fileURLWithPath: "/nonexistent"), runner: FakeRunner(), monotonic: { .seconds(5) })
        #expect(DeadlineRunner.deadline(for: unset) == .milliseconds(123_500))
    }
}

/// A runner that records each command's time limit and answers `answer`, having run `after` as a command's time passing.
final class TimingRunner: CommandRunning {
    let answer: CommandResult
    let after: @Sendable () -> Void
    let recorded = Mutex<[Duration]>([])
    var timeouts: [Duration] { recorded.withLock { $0 } }

    init(answer: CommandResult = CommandResult(status: 0), after: @escaping @Sendable () -> Void = {}) {
        self.answer = answer
        self.after = after
    }

    func run(_ argv: [String], stdin: Data?, timeout: Duration) async -> CommandResult {
        recorded.withLock { $0.append(timeout) }
        after()
        return answer
    }

    func which(_ name: String) -> String? { nil }
}
