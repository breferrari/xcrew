import Foundation
import Synchronization

/// Runs at most `size` commands at once and queues the rest, for a reading that starts many heavy commands together:
/// each `xccov` holds about 100 MB, and started all at once they crowd the Mac's cores and memory. Every command its
/// caller runs goes through it, `git`'s too. It's sized to the Mac's performance cores, past which a call's time grows
/// (docs/findings.md, *The branch's test runs*), read when the first command comes, so a caller that starts none reads
/// nothing. A waiting command goes by its lane, a lower one first, then by when it came; one cancelled while it waits
/// leaves the queue at once.
public final class CommandPool: CommandRunning {
    private let base: any CommandRunning
    private let size: Once<Int>
    private let slots = Mutex(Slots())

    /// The pool's commands running, and those waiting, each with its lane and when it came.
    private struct Slots {
        var running = 0
        var waiting: [(id: Int, lane: Int, waiter: CheckedContinuation<Bool, Never>)] = []
        var next = 0
    }

    public init(_ base: any CommandRunning, size: Int) {
        self.base = base
        self.size = Once { max(1, size) }
    }

    /// A pool sized to the Mac's performance cores, asked of `base` when the first command comes.
    public init(sizedToCores base: any CommandRunning) {
        self.base = base
        self.size = Once { await Self.size(using: base) }
    }

    public func run(_ argv: [String], stdin: Data?, timeout: Duration) async -> CommandResult {
        await run(argv, stdin: stdin, timeout: timeout, lane: 0)
    }

    /// The command's answer once a slot is free, its turn by `lane`; one cancelled while it waits isn't started, and
    /// answers as timed out.
    public func run(_ argv: [String], stdin: Data?, timeout: Duration, lane: Int) async -> CommandResult {
        guard await acquire(await size.value(), lane: lane) else { return .timedOut }
        defer { release() }
        guard !Task.isCancelled else { return .timedOut }
        return await base.run(argv, stdin: stdin, timeout: timeout)
    }

    public func which(_ name: String) -> String? { base.which(name) }

    /// How many commands wait for a slot, for tests that wait for a queue to form.
    var waiting: Int { slots.withLock { $0.waiting.count } }

    /// The lanes of the commands that wait, in their turn, for tests that check where a caller's commands go.
    var waitingLanes: [Int] { slots.withLock { $0.waiting.map(\.lane) } }

    /// Whether a slot was taken: false when the task was cancelled while it waited.
    private func acquire(_ size: Int, lane: Int) async -> Bool {
        let id = slots.withLock { slots in
            defer { slots.next += 1 }
            return slots.next
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (waiter: CheckedContinuation<Bool, Never>) in
                let answer: Bool? = slots.withLock { slots in
                    if Task.isCancelled { return false }
                    guard slots.running < size else {
                        let at = slots.waiting.firstIndex { $0.lane > lane } ?? slots.waiting.endIndex
                        slots.waiting.insert((id, lane, waiter), at: at)
                        return nil
                    }
                    slots.running += 1
                    return true
                }
                if let answer { waiter.resume(returning: answer) }
            }
        } onCancel: {
            let waiter = slots.withLock { slots in
                slots.waiting.firstIndex { $0.id == id }.map { slots.waiting.remove(at: $0).waiter }
            }
            waiter?.resume(returning: false)
        }
    }

    private func release() {
        let next = slots.withLock { slots -> CheckedContinuation<Bool, Never>? in
            guard !slots.waiting.isEmpty else {
                slots.running -= 1
                return nil
            }
            return slots.waiting.removeFirst().waiter
        }
        next?.resume(returning: true)
    }

    /// The Mac's performance cores (`hw.perflevel0.physicalcpu`), else its active cores (`hw.activecpu`), else one.
    public static func size(using runner: any CommandRunning) async -> Int {
        for key in ["hw.perflevel0.physicalcpu", "hw.activecpu"] {
            let answer = await runner.run("sysctl", "-n", key, timeout: DeadlineRunner.untimed)
            if answer.succeeded, let count = Int(answer.stdout.trimmingCharacters(in: .whitespacesAndNewlines)), count > 0 { return count }
        }
        return 1
    }

    /// `runner`'s commands in `lane` of its pool, behind lower lanes' waiting ones; a runner that isn't a pool is as it is.
    public static func lane(of runner: any CommandRunning, _ lane: Int) -> any CommandRunning {
        (runner as? CommandPool).map { Lane(pool: $0, lane: lane) } ?? runner
    }

    /// A pool's commands in one lane.
    private struct Lane: CommandRunning {
        let pool: CommandPool
        let lane: Int

        func run(_ argv: [String], stdin: Data?, timeout: Duration) async -> CommandResult {
            await pool.run(argv, stdin: stdin, timeout: timeout, lane: lane)
        }

        func which(_ name: String) -> String? { pool.which(name) }
    }
}

extension Machine {
    /// This machine with its commands run through a pool sized to its performance cores.
    public func pooled() -> Machine {
        running(CommandPool(sizedToCores: runner))
    }
}
