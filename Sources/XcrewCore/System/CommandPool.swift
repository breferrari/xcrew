import Foundation
import Synchronization

/// Runs at most `size` commands at once and queues the rest, for a reading that starts many heavy commands together:
/// each `xccov` holds about 100 MB, and started all at once they crowd the Mac's cores and memory. Sized to the Mac's
/// performance cores, past which a call's time grows (docs/findings.md, *The branch's test runs*), read when the first
/// command comes, so a caller that starts none reads nothing.
public final class CommandPool: CommandRunning {
    let base: any CommandRunning
    let size: Once<Int>
    private let slots = Mutex<(running: Int, waiting: [CheckedContinuation<Void, Never>])>((0, []))

    public init(_ base: any CommandRunning, size: Int) {
        self.base = base
        self.size = Once { max(1, size) }
    }

    /// A pool sized to the Mac's performance cores, asked of `base` when the first command comes.
    public init(sizedToCores base: any CommandRunning) {
        self.base = base
        self.size = Once { await Self.size(using: base) }
    }

    /// The command's answer once a slot is free; one cancelled while it waited isn't started, and answers as timed out.
    public func run(_ argv: [String], stdin: Data?, timeout: Duration) async -> CommandResult {
        await acquire(await size.value())
        defer { release() }
        guard !Task.isCancelled else { return .timedOut }
        return await base.run(argv, stdin: stdin, timeout: timeout)
    }

    public func which(_ name: String) -> String? { base.which(name) }

    private func acquire(_ size: Int) async {
        await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
            let started = slots.withLock { slots in
                guard slots.running < size else {
                    slots.waiting.append(waiter)
                    return false
                }
                slots.running += 1
                return true
            }
            if started { waiter.resume() }
        }
    }

    private func release() {
        let next = slots.withLock { slots -> CheckedContinuation<Void, Never>? in
            guard !slots.waiting.isEmpty else {
                slots.running -= 1
                return nil
            }
            return slots.waiting.removeFirst()
        }
        next?.resume()
    }

    /// The Mac's performance cores (`hw.perflevel0.physicalcpu`), else its active cores (`hw.activecpu`), else one.
    public static func size(using runner: any CommandRunning) async -> Int {
        for key in ["hw.perflevel0.physicalcpu", "hw.activecpu"] {
            let answer = await runner.run("sysctl", "-n", key, timeout: .seconds(5))
            if answer.succeeded, let count = Int(answer.stdout.trimmingCharacters(in: .whitespacesAndNewlines)), count > 0 { return count }
        }
        return 1
    }
}

extension Machine {
    /// This machine with its commands run through a pool sized to its performance cores.
    public func pooled() -> Machine {
        Machine(environment: environment, home: home, runner: CommandPool(sizedToCores: runner), processID: processID, applications: applications, now: now)
    }
}
