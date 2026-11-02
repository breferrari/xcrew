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

    /// A command the deadline cut short, timed out within the time left, is named as cut; one past its own limit isn't.
    @Test func aCommandCutShortIsNamed() async {
        let runner = DeadlineRunner(TimingRunner(answer: .timedOut), deadline: Self.start.addingTimeInterval(4), now: { Self.start })
        _ = await runner.run(["xcrun", "xcresulttool", "get"], stdin: nil, timeout: .seconds(15))
        _ = await runner.run(["git", "diff"], stdin: nil, timeout: .seconds(2))
        #expect(runner.cut == ["xcresulttool"])
    }

    /// The CLI takes its deadline from the time the mod gives it, less what it needs to answer.
    @Test func theCLIsDeadlineIsTheTimeItIsGiven() {
        let machine = Machine(environment: ["XCREW_WITHIN_MS": "10000"], home: URL(fileURLWithPath: "/nonexistent"), runner: FakeRunner(), now: { Self.start })
        #expect(DeadlineRunner.deadline(for: machine) == Self.start.addingTimeInterval(10 - DeadlineRunner.answering.seconds))
        let unset = Machine(environment: [:], home: URL(fileURLWithPath: "/nonexistent"), runner: FakeRunner(), now: { Self.start })
        #expect(DeadlineRunner.deadline(for: unset) == Self.start.addingTimeInterval(DeadlineRunner.asked.seconds - DeadlineRunner.answering.seconds))
    }
}

/// A runner that records each command's time limit and answers `answer`.
final class TimingRunner: CommandRunning {
    let answer: CommandResult
    let recorded = Mutex<[Duration]>([])
    var timeouts: [Duration] { recorded.withLock { $0 } }

    init(answer: CommandResult = CommandResult(status: 0)) { self.answer = answer }

    func run(_ argv: [String], stdin: Data?, timeout: Duration) async -> CommandResult {
        recorded.withLock { $0.append(timeout) }
        return answer
    }

    func which(_ name: String) -> String? { nil }
}

extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
