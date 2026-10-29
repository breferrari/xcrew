import Foundation

/// A test run's counts, as both servers' JSON gives them.
struct TestCounts: Decodable, Sendable {
    @Lenient var passed: Int?
    @Lenient var failed: Int?
    @Lenient var skipped: Int?
    @Lenient var total: Int?

    init(passed: Int?, failed: Int?, skipped: Int?, total: Int? = nil) {
        _passed = Lenient(wrappedValue: passed)
        _failed = Lenient(wrappedValue: failed)
        _skipped = Lenient(wrappedValue: skipped)
        _total = Lenient(wrappedValue: total)
    }

    var sum: Int { (passed ?? 0) + (failed ?? 0) + (skipped ?? 0) }
    /// How many tests ran: the total when the server gives one.
    var ran: Int { total ?? sum }
}
