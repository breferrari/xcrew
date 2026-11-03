import Foundation
import Synchronization
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// One pool for the heavy commands a reading starts at once: at most its size run together, the rest wait their turn.
@Suite struct CommandPoolTests {
    /// Twenty commands through a pool of three: never more than three at once, and every one answered.
    @Test func noMoreThanItsSizeRunAtOnce() async {
        let counting = CountingRunner(gate: 3, total: 20)
        let pool = CommandPool(counting, size: 3)
        let answers = await withTaskGroup(of: CommandResult.self) { group in
            for index in 0..<20 { group.addTask { await pool.run(["xcrun", "xccov", "\(index)"], stdin: nil) } }
            return await group.reduce(into: [CommandResult]()) { $0.append($1) }
        }
        #expect(answers.count == 20 && answers.allSatisfy(\.succeeded))
        #expect(counting.peak == 3)
    }

    /// A lower lane goes first: with one slot held, the waiting commands of lane 0 run before lane 1's, whatever order
    /// they came in.
    @Test func aLowerLaneGoesFirst() async {
        let order = OrderRunner()
        let pool = CommandPool(order, size: 1)
        let holding = Task { await pool.run(["hold"], stdin: nil, lane: 0) }
        await order.started("hold")
        let later = Task { await pool.run(["later"], stdin: nil, lane: 1) }
        await order.waitingFor(pool, count: 1)
        let sooner = Task { await pool.run(["sooner"], stdin: nil, lane: 0) }
        await order.waitingFor(pool, count: 2)
        order.release("hold")
        _ = await (holding.value, later.value, sooner.value)
        #expect(order.ran == ["hold", "sooner", "later"])
    }

    /// A command cancelled while it waits leaves the queue at once, answered as cancelled, without waiting for a slot.
    @Test func aCancelledWaiterLeavesAtOnce() async {
        let order = OrderRunner()
        let pool = CommandPool(order, size: 1)
        let holding = Task { await pool.run(["hold"], stdin: nil) }
        await order.started("hold")
        let waiting = Task { await pool.run(["waiting"], stdin: nil) }
        await order.waitingFor(pool, count: 1)
        waiting.cancel()
        #expect(await waiting.value == .cancelled)
        #expect(pool.waiting == 0)
        order.release("hold")
        _ = await holding.value
        #expect(order.ran == ["hold"])
    }

    /// Sized to the Mac's performance cores, else its active ones, else one at a time.
    @Test func itsSizeIsThePerformanceCores() async {
        let both = FakeRunner(responses: ["sysctl -n hw.perflevel0.physicalcpu": .init(status: 0, stdout: "8\n"), "sysctl -n hw.activecpu": .init(status: 0, stdout: "10\n")])
        #expect(await CommandPool.size(using: both) == 8)
        let noLevels = FakeRunner(responses: ["sysctl -n hw.perflevel0.physicalcpu": .init(status: 1, stderr: "unknown oid"), "sysctl -n hw.activecpu": .init(status: 0, stdout: "4\n")])
        #expect(await CommandPool.size(using: noLevels) == 4)
        #expect(await CommandPool.size(using: FakeRunner()) == 1)
    }
}

/// A runner that answers every command after a short wait, counting how many run at once.
final class CountingRunner: CommandRunning {
    /// Each command is held until `gate` run at once, or until the last of `total` has started: a pool that let more run
    /// together shows it in `peak`, with no wait on time.
    let gate: Int
    let total: Int
    let counts = Mutex<(now: Int, peak: Int, started: Int, held: [CheckedContinuation<Void, Never>])>((0, 0, 0, []))
    var peak: Int { counts.withLock { $0.peak } }

    init(gate: Int, total: Int) { (self.gate, self.total) = (gate, total) }

    func run(_ argv: [String], stdin: Data?) async -> CommandResult {
        await withCheckedContinuation { (held: CheckedContinuation<Void, Never>) in
            let released = counts.withLock { counts -> [CheckedContinuation<Void, Never>] in
                counts.now += 1
                counts.started += 1
                counts.peak = max(counts.peak, counts.now)
                counts.held.append(held)
                guard counts.now >= gate || counts.started == total else { return [] }
                defer { counts.held = [] }
                return counts.held
            }
            released.forEach { $0.resume() }
        }
        counts.withLock { $0.now -= 1 }
        return CommandResult(status: 0)
    }

    func which(_ name: String) -> String? { nil }
}

/// A runner whose commands each run until released, recording the order they started in.
final class OrderRunner: CommandRunning {
    let state = Mutex<(ran: [String], held: [String: CheckedContinuation<Void, Never>], seen: Set<String>)>(([], [:], []))
    var ran: [String] { state.withLock { $0.ran } }

    func run(_ argv: [String], stdin: Data?) async -> CommandResult {
        let name = argv.first ?? ""
        await withCheckedContinuation { (held: CheckedContinuation<Void, Never>) in
            let free = state.withLock { state in
                state.ran.append(name)
                state.seen.insert(name)
                guard name == "hold" else { return true }
                state.held[name] = held
                return false
            }
            if free { held.resume() }
        }
        return CommandResult(status: 0)
    }

    func which(_ name: String) -> String? { nil }

    /// Waits until the command named `name` has started.
    func started(_ name: String) async {
        while !state.withLock({ $0.seen.contains(name) }) { await Task.yield() }
    }

    /// Waits until `count` commands wait in `pool`.
    func waitingFor(_ pool: CommandPool, count: Int) async {
        while pool.waiting < count { await Task.yield() }
    }

    func release(_ name: String) {
        state.withLock { $0.held.removeValue(forKey: name) }?.resume()
    }
}
