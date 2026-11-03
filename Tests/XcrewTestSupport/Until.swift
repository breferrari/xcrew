import Foundation
import Testing

/// Waits for `condition`, which another thread makes true, checking it every 10 ms: a condition that reads a file slows
/// the work it waits on when checked more often. Past `limit`, a hang guard, it fails at the caller's line.
public func until(giveUpAfter limit: Duration = .seconds(500), sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool) async throws {
    let tries = Int(limit / .milliseconds(10))
    for _ in 0..<tries where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    try #require(condition(), "never came true", sourceLocation: sourceLocation)
}
