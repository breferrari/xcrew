import Foundation
import Synchronization
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// One pool for the heavy commands a reading starts at once: at most its size run together, the rest wait their turn.
@Suite struct CommandPoolTests {
    /// Twenty commands through a pool of three: never more than three at once, and every one answered.
    @Test func noMoreThanItsSizeRunAtOnce() async {
        let counting = CountingRunner()
        let pool = CommandPool(counting, size: 3)
        let answers = await withTaskGroup(of: CommandResult.self) { group in
            for index in 0..<20 { group.addTask { await pool.run(["xcrun", "xccov", "\(index)"], stdin: nil, timeout: .seconds(5)) } }
            return await group.reduce(into: [CommandResult]()) { $0.append($1) }
        }
        #expect(answers.count == 20 && answers.allSatisfy(\.succeeded))
        #expect(counting.peak == 3)
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
    let counts = Mutex((now: 0, peak: 0))
    var peak: Int { counts.withLock { $0.peak } }

    func run(_ argv: [String], stdin: Data?, timeout: Duration) async -> CommandResult {
        counts.withLock { $0.now += 1; $0.peak = max($0.peak, $0.now) }
        try? await Task.sleep(for: .milliseconds(20))
        counts.withLock { $0.now -= 1 }
        return CommandResult(status: 0)
    }

    func which(_ name: String) -> String? { nil }
}
