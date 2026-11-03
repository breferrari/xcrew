import Foundation

/// Waits for `condition`, which another thread makes true, checking it every 10 ms: a condition that reads a file slows
/// the work it waits on when checked more often. It waits until the condition holds, however long that takes: a test
/// passes or fails on what it asserts, not on time (docs/findings.md, *No budgets*).
public func until(_ condition: () -> Bool) async throws {
    while !condition() { try await Task.sleep(for: .milliseconds(10)) }
}

/// Waits for `condition` as `until` does, for a condition that reads something by running a program.
public func until(_ condition: () async -> Bool) async throws {
    while await !condition() { try await Task.sleep(for: .milliseconds(10)) }
}
