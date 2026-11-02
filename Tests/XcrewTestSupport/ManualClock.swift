import Synchronization

/// A clock that moves only when a test moves it, so code that waits on a clock is tested by events, not elapsed time.
/// A sleep resumes once `advance` passes its deadline; `sleepers` says how many are waiting.
public final class ManualClock: Clock, Sendable {
    public struct Instant: InstantProtocol, Sendable {
        public let offset: Duration

        public func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        public func duration(to other: Instant) -> Duration { other.offset - offset }
        public static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct State {
        var now = Instant(offset: .zero)
        var next = 0
        var waiting: [Int: (deadline: Instant, continuation: CheckedContinuation<Void, any Error>)] = [:]
    }

    private let state = Mutex(State())

    public init() {}

    public var now: Instant { state.withLock { $0.now } }
    public var minimumResolution: Duration { .nanoseconds(1) }
    /// How many sleeps are waiting.
    public var sleepers: Int { state.withLock { $0.waiting.count } }

    /// Resumes once `advance` passes `deadline`, or throws `CancellationError` once its task is cancelled, as a clock's
    /// sleep does: a task group waiting on its children never waits on a sleep nobody will end.
    public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        let id = state.withLock { state -> Int in
            state.next += 1
            return state.next
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let resumeNow = state.withLock { state -> Bool in
                    if Task.isCancelled || deadline <= state.now { return true }
                    state.waiting[id] = (deadline, continuation)
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        } onCancel: {
            state.withLock { $0.waiting.removeValue(forKey: id) }?.continuation.resume(throwing: CancellationError())
        }
        try Task.checkCancellation()
    }

    /// Moves the clock on, resuming each sleep whose deadline it passes.
    public func advance(by duration: Duration) {
        let due = state.withLock { state -> [CheckedContinuation<Void, any Error>] in
            state.now = state.now.advanced(by: duration)
            let now = state.now
            let due = state.waiting.filter { $0.value.deadline <= now }
            for id in due.keys { state.waiting.removeValue(forKey: id) }
            return due.values.map(\.continuation)
        }
        due.forEach { $0.resume() }
    }
}
