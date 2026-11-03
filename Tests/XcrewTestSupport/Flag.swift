import Synchronization

/// A flag one task sets and a test reads, as a class holding its lock: a closure captures the class, never a local
/// `Mutex`, which some Swift compilers reject in a closure that may run concurrently (docs/findings.md, *Toolchains*).
public final class Flag: Sendable {
    private let state = Mutex(false)

    public init() {}

    public var isSet: Bool { state.withLock { $0 } }

    public func set() {
        state.withLock { $0 = true }
    }
}
