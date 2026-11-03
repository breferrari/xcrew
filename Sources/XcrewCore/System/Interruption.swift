import Dispatch
import Foundation
import Synchronization

/// Runs work that a signal the process watches cancels, as Claude Code or a person's Ctrl-C stops the CLI: a cancelled
/// run stops the program it ran, sending SIGTERM to that program's group, so what the CLI started is stopped with it
/// (docs/findings.md, *Stopping a program*). A second signal while the work goes on ends the process at once, for work
/// that doesn't stop when cancelled; the programs it started already had the first's SIGTERM. A signal whose handler
/// runs once the work has returned stops nothing; one handled before, even as the work returns, counts as its stop.
public enum Interruption {
    /// What a watched signal does: stop the work, end the process as the second while the work goes on, or nothing once
    /// it has ended.
    enum Effect {
        case stop
        case end
        case ignored
    }

    /// What the handlers share: the signal that stopped the work, whether the work has ended, and how to cancel it.
    final class State: Sendable {
        let value = Mutex<(signal: Int32?, ended: Bool, cancel: (@Sendable () -> Void)?)>((nil, false, nil))
    }

    /// The signal sources installed, kept for the process's life: one released stops watching.
    static let watching = Mutex<[any DispatchSourceSignal]>([])

    /// The work's value, and the watched signal that stopped it, if one did.
    public static func run<Success: Sendable>(on signals: [Int32], _ work: @escaping @Sendable () async -> Success) async -> (value: Success, signal: Int32?) {
        let state = State()
        let sources = signals.map { number in
            Darwin.signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler {
                let (effect, cancel) = state.value.withLock { value -> (Effect, (@Sendable () -> Void)?) in
                    guard !value.ended else { return (.ignored, nil) }
                    guard value.signal == nil else { return (.end, nil) }
                    value.signal = number
                    return (.stop, value.cancel)
                }
                switch effect {
                case .stop:
                    cancel?()
                    for watched in signals { Darwin.signal(watched, SIG_DFL) }
                case .end:
                    Darwin.signal(number, SIG_DFL)
                    raise(number)
                case .ignored:
                    break
                }
            }
            source.resume()
            return source
        }
        watching.withLock { $0 += sources }
        let task = Task {
            let value = await work()
            state.value.withLock { $0.ended = true }
            return value
        }
        let stoppedAlready = state.value.withLock { value -> Bool in
            value.cancel = { task.cancel() }
            return value.signal != nil
        }
        if stoppedAlready { task.cancel() }
        let value = await task.value
        return (value, state.value.withLock { $0.signal })
    }
}
