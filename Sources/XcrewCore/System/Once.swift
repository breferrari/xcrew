import Foundation

/// Runs its work once, however many callers ask, and hands each of them the result.
public actor Once<Value: Sendable> {
    private let work: @Sendable () async -> Value
    private var running: Task<Value, Never>?

    init(_ work: @escaping @Sendable () async -> Value) {
        self.work = work
    }

    public func value() async -> Value {
        if let running { return await running.value }
        let task = Task { await work() }
        running = task
        return await task.value
    }
}
