import Foundation

/// A test run's counts, as both servers' JSON gives them and MobileBuildMCP's text writes them.
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

    /// The run's verdict from these counts, the same whichever shape gave them: none counted is no test ran, which is a
    /// fact and not a pass; a failure fails, after it the first failing test when one is named; else how many passed.
    func summary(succeeded: Bool, failing first: String? = nil) -> ToolOutput.Summary {
        if sum == 0 { return ToolOutput.Summary(ok: false, detail: ToolOutput.noTestsRan) }
        if let failed, failed > 0 { return ToolOutput.Summary(ok: false, detail: "\(failed) of \(sum) failed\(first.map { " · \($0)" } ?? "")") }
        return ToolOutput.Summary(ok: succeeded, detail: "\(passed ?? 0) passed")
    }
}
