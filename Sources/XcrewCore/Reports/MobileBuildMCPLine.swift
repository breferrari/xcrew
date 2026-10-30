import Foundation

/// The lines MobileBuildMCP's text output is made of, each shape read here and nowhere else.
/// Its emoji markers are matched by scalar: `⏭️` is `⏭` and a variation selector, one character
/// that a character-level match misses.
enum MobileBuildMCPLine {
    /// `🧪 …`, the first line of a test run's text, whatever follows the marker.
    static func isTestRunHeader(_ line: String) -> Bool {
        line.hasPrefix("🧪")
    }

    /// `🧪 Test`, the header of the test run whose list compaction knows.
    static func isTestHeader(_ line: String) -> Bool {
        line.hasPrefix("🧪 Test")
    }

    enum Heading: Equatable {
        /// `Test Results:`, the list of every test with its outcome.
        case testResults
        /// `Test Failures (2):`, each failing test with its message.
        case testFailures
        /// `Errors (3):`, a failing build's errors.
        case errors
    }

    static func heading(_ line: String) -> Heading? {
        if line == "Test Results:" { return .testResults }
        if line.hasPrefix("Test Failures") { return .testFailures }
        return errorCount(in: line) != nil ? .errors : nil
    }

    /// `❌ Test failed`: a test run that ended before its tests ran.
    static func isTestRunFailure(_ line: String) -> Bool {
        line.contains("❌ Test failed")
    }

    /// `❌ Build failed`.
    static func isBuildFailure(_ line: String) -> Bool {
        line.contains("❌ Build failed")
    }

    /// A Test Results line of a test that failed.
    static func isFailed(_ line: String) -> Bool {
        line.contains("❌")
    }

    /// `✗ <entry>`: a failing test or a compile error, as the Test Failures and Errors sections list them.
    static func entry(_ line: String) -> String? {
        line.firstMatch(of: #/^\s*✗ (.+)$/#).map { String($0.1) }
    }

    /// `⚠ <message> [#Group]`, a compiler warning as the Warnings section lists it.
    static func warning(_ line: String) -> (indent: String, message: String)? {
        line.firstMatch(of: #/^(\s*)⚠ (.+)$/#).map { (String($0.1), String($0.2)) }
    }

    /// `LLVM Profile Error: Failed to write file "default.profraw": …`, the coverage runtime failing to write its profile,
    /// such as in a folder it may not write to: the run goes on, so it is no error of the run's. Its other errors are.
    static func isCoverageRuntime(_ entry: String) -> Bool {
        entry.hasPrefix(#"LLVM Profile Error: Failed to write file ""#) && entry.contains(#".profraw":"#)
    }

    /// `| \`- error: …`, the compiler's excerpt of an error listed just above, as an entry of its own.
    static func isExcerpt(_ entry: String) -> Bool {
        entry.hasPrefix("|")
    }

    /// `Suite / test(): message`, the part of a failing test's line after its `✗`.
    static func test(in entry: String) -> (test: TestID, message: String)? {
        entry.firstMatch(of: #/^(.+?) \/ (\S+?): (.*)$/#).map { (TestID(suite: $0.1, name: $0.2), String($0.3)) }
    }

    /// `    /path/File.swift:12`, the line after a failure, an error or a warning that says where it happened.
    static func location(_ line: String) -> (path: String, line: String)? {
        line.firstMatch(of: #/^\s+(\/.*\S)\s*$/#).flatMap { place(String($0.1)) }
    }

    /// `/path/File.swift:12`, or `:12:5` with a column, which stays with the line; the path may hold spaces.
    static func place(_ text: String) -> (path: String, line: String)? {
        text.firstMatch(of: #/^(.+?):(\d+(?::\d+)?)$/#).map { (String($0.1), String($0.2)) }
    }

    /// `⏭️ Suite/test() (0.000s)`, a skipped test.
    static func skipped(_ line: String) -> TestID? {
        line.firstMatch(of: #/^\s*⏭\x{FE0F}? (\S+?)\/(\S+?) \(/#.matchingSemantics(.unicodeScalar)).map { TestID(suite: $0.1, name: $0.2) }
    }

    /// The line Xcrew adds under a skipped test, saying why it was skipped.
    static func skipReason(_ reason: String) -> String {
        "      skipped: \(reason)"
    }

    static func isSkipReason(_ line: String) -> Bool {
        line.contains(#/^\s+skipped: /#)
    }

    /// Whether a Test Results line is a skipped test's, whatever follows the marker.
    static func isSkipped(_ line: String) -> Bool {
        line.unicodeScalars.contains("⏭")
    }

    /// `✅ Suite/test() (0.001s)`, a passing test in the Test Results list.
    static func isPassed(_ line: String) -> Bool {
        line.drop { $0 == " " }.hasPrefix("✅")
    }

    /// `❌ 2 tests failed, 959 passed, 1 skipped (⏱️ 47.4s)`, the run's summary line.
    static func isSummary(_ line: String) -> Bool {
        line.contains(#/^(❌|✅) \d+ tests? /#)
    }

    /// A failing run's counts, from its summary line.
    static func counts(in line: String) -> TestCounts? {
        line.firstMatch(of: #/❌ (\d+) tests? failed, (\d+) passed, (\d+) skipped/#).map { TestCounts(passed: Int($0.2) ?? 0, failed: Int($0.1) ?? 0, skipped: Int($0.3) ?? 0) }
    }

    /// How many tests a summary line, passing or failing, counts as skipped.
    static func skippedCount(in line: String) -> Int? {
        line.firstMatch(of: #/^(?:❌|✅) \d+ tests? .*?(\d+) skipped/#).flatMap { Int($0.1) }
    }

    /// `(⏱️ 12.3s)`, how long the run took, in seconds.
    static func duration(in line: String) -> Double? {
        line.firstMatch(of: #/\(⏱️ ([\d.]+)s\)/#).flatMap { Double($0.1) }
    }

    /// `└── ~/Library/…/workspace/`, the folder a failing test run's artifacts are under.
    static func workspaceFolder(_ line: String) -> String? {
        line.firstMatch(of: #/└── (~?\/\S+\/)\s*$/#).map { String($0.1) }
    }

    /// `result-bundles/….xcresult — Result Bundle`, the run's bundle, under the workspace folder.
    static func resultBundle(_ line: String) -> String? {
        line.firstMatch(of: #/(result-bundles\/\S+\.xcresult) — Result Bundle/#).map { String($0.1) }
    }

    /// `….log — Build Logs`: the run's build log, by its full path or under the workspace folder.
    static func buildLog(_ line: String) -> String? {
        guard line.contains(" — Build Logs") else { return nil }
        return line.firstMatch(of: #/(\S+\.log) — Build Logs/#).map { String($0.1) }
    }

    /// `Test Failures (4):`, the head of a failing run's list of failures, and where its count is written.
    static func failureCount(in line: String) -> (range: Range<String.Index>, count: Int)? {
        line.firstMatch(of: #/^Test Failures \((\d+)\):/#).flatMap { match in Int(match.1).map { (match.range, $0) } }
    }

    /// The Swift runtime's message for a trap, from an error the run lists (`App/Queue.swift:12: Fatal error: …`, the
    /// xctest log's prefix or not): a fatal error, a failed precondition or a failed assertion.
    static func runtimeError(_ message: String) -> String? {
        message.firstMatch(of: #/\.swift:\d+: ((?:Fatal error|Precondition failed|Assertion failed): .*)$/#).map { String($0.1) }
    }

    /// `Errors (3):`, the head of a failing build's error list, and where its count is written.
    static func errorCount(in line: String) -> (range: Range<String.Index>, count: Int)? {
        line.firstMatch(of: #/^Errors \((\d+)\):/#).flatMap { match in Int(match.1).map { (match.range, $0) } }
    }
}
