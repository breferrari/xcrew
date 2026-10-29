import Foundation
import Synchronization

/// A pipe's output as it arrives, until end of file or until the runner stops waiting for it.
final class Drain: Sendable {
    private struct State {
        var data = Data()
        var isEnded = false
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

    /// What has arrived so far.
    var text: String {
        String(decoding: state.withLock { $0.data }, as: UTF8.self)
    }
}
