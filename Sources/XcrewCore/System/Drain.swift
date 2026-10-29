import Foundation
import Synchronization

/// A pipe's output as it arrives, until end of file or until the runner stops waiting for it.
final class Drain: Sendable {
    private struct State {
        var data = Data()
        var isEnded = false
        /// Whether reading stopped because nothing new arrived in time, rather than at end of file.
        var wentQuiet = false
        var waiter: CheckedContinuation<Void, Never>?
    }

    private let handle: FileHandle
    private let state = Mutex(State())

    init(_ handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { stop() } else { state.withLock { if !$0.isEnded { $0.data.append(chunk) } } }
        }
    }

    /// Stops reading; reaching end of file and giving up on the pipe both end here.
    func stop() {
        handle.readabilityHandler = nil
        let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.isEnded = true
            let waiter = state.waiter
            state.waiter = nil
            return waiter
        }
        waiter?.resume()
    }

    /// Returns once reading has stopped.
    func ended() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isEnded = state.withLock { state -> Bool in
                if !state.isEnded { state.waiter = continuation }
                return state.isEnded
            }
            if isEnded { continuation.resume() }
        }
    }

    /// Returns once reading has stopped, stopping it at `deadline` if end of file hasn't come by then.
    func ended(by deadline: ContinuousClock.Instant) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.ended() }
            group.addTask {
                try? await Task.sleep(until: deadline, clock: .continuous)
                self.stop()
            }
            await group.next()
            group.cancelAll()
        }
    }

    /// Returns once reading has stopped, stopping it once `idle` passes with nothing new arriving: true at end of file,
    /// false when the pipe went quiet without closing.
    func ended(idleFor idle: Duration) async -> Bool {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.ended() }
            group.addTask {
                while !Task.isCancelled {
                    let seen = self.data.count
                    try? await Task.sleep(for: idle)
                    if Task.isCancelled { return }
                    if self.data.count == seen {
                        self.state.withLock { $0.wentQuiet = true }
                        self.stop()
                        return
                    }
                }
            }
            await group.next()
            group.cancelAll()
        }
        return !state.withLock { $0.wentQuiet }
    }

    /// What has arrived so far.
    var data: Data { state.withLock { $0.data } }

    /// What has arrived so far, as text.
    var text: String { String(decoding: data, as: UTF8.self) }
}
