import Foundation

/// Waits for `condition`, which another thread makes true, checking it every 10 ms: a condition that reads a file, as a
/// shim test's does, slows the build it waits on when checked more often. Past a hang guard as long as a shim test's
/// build may take, throws `Until.NeverCameTrue`.
public func until(_ condition: () -> Bool) async throws {
    for _ in 0..<50_000 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    guard condition() else { throw Until.NeverCameTrue() }
}

/// What `until` throws.
public enum Until {
    /// A condition that never came true within the hang guard.
    public struct NeverCameTrue: Error, CustomStringConvertible {
        public var description: String { "never came true" }
    }
}
