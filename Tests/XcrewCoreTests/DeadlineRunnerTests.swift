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
        let runner = DeadlineRunner(recording, deadline: Self.start.addingTimeInterval(4), now: { Self.start })
        _ = await runner.run(["xcrun", "xccov", "view"], stdin: nil, timeout: .seconds(15))
        _ = await runner.run(["git", "diff"], stdin: nil, timeout: .seconds(2))
        #expect(recording.timeouts == [.seconds(4), .seconds(2)])
        #expect(runner.cut.isEmpty)
    }

    /// Past the deadline a command isn't started: it answers as timed out, and is named as cut.
    @Test func pastTheDeadlineACommandIsntStarted() async {
        let recording = TimingRunner()
        let runner = DeadlineRunner(recording, deadline: Self.start, now: { Self.start.addingTimeInterval(1) })
        #expect(await runner.run(["xcrun", "xccov", "view"], stdin: nil, timeout: .seconds(15)) == .timedOut)
        #expect(recording.timeouts.isEmpty)
        #expect(runner.cut == ["xccov"])
    }

    /// A command that timed out once the deadline had passed is named as cut; one that timed out before it, at its own
    /// limit or cancelled, isn't.
    @Test func aCommandTheDeadlineStoppedIsNamed() async {
        let clock = Mutex(Self.start)
        let runner = DeadlineRunner(TimingRunner(answer: .timedOut, after: { clock.withLock { $0 = $0.addingTimeInterval(2) } }), deadline: Self.start.addingTimeInterval(3), now: { clock.withLock { $0 } })
        _ = await runner.run(["git", "diff"], stdin: nil, timeout: .seconds(2))
        #expect(runner.cut.isEmpty)
        _ = await runner.run(["xcrun", "xcresulttool", "get"], stdin: nil, timeout: .seconds(15))
        #expect(runner.cut == ["xcresulttool"])
        // Cancelled with time still left, its limit shortened or not: the deadline didn't stop it.
        let cancelled = DeadlineRunner(TimingRunner(answer: .timedOut), deadline: Self.start.addingTimeInterval(3), now: { Self.start })
        _ = await cancelled.run(["xcrun", "xccov", "view"], stdin: nil, timeout: .seconds(15))
        #expect(cancelled.cut.isEmpty)
    }

    /// What the CLI keeps to answer outlasts the time a stopped command's output is waited for, so a cut command can't
    /// hold the answer past the caller's limit.
    @Test func theTimeKeptToAnswerOutlastsAStoppedCommandsGrace() {
        #expect(DeadlineRunner.answering > SystemCommandRunner.grace)
    }

    /// The CLI takes its deadline from the time the mod gives it, less what it needs to answer.
    @Test func theCLIsDeadlineIsTheTimeItIsGiven() {
        let machine = Machine(environment: ["XCREW_WITHIN_MS": "10000"], home: URL(fileURLWithPath: "/nonexistent"), runner: FakeRunner(), now: { Self.start })
        #expect(DeadlineRunner.deadline(for: machine) == Self.start.addingTimeInterval(8.5))
        let unset = Machine(environment: [:], home: URL(fileURLWithPath: "/nonexistent"), runner: FakeRunner(), now: { Self.start })
        #expect(DeadlineRunner.deadline(for: unset) == Self.start.addingTimeInterval(118.5))
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
