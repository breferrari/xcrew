import Foundation

/// The lines MobileBuildMCP's text output is made of, each shape read here and nowhere else.
/// Its emoji markers are matched by scalar: `⏭️` is `⏭` and a variation selector, one character
/// that a character-level match misses.
enum MobileBuildMCPLine {
    /// A test as `Suite/test`: MobileBuildMCP lists one failure both with and without the `()`.
    static func key(_ suite: some StringProtocol, _ test: some StringProtocol) -> String {
        "\(suite)/\(test.hasSuffix("()") ? test.dropLast(2) : test[...])"
    }

    /// `✗ <entry>`: a failing test or a compile error, as the Test Failures and Errors sections list them.
    static func entry(_ line: String) -> String? {
        line.firstMatch(of: #/^\s*✗ (.+)$/#).map { String($0.1) }
    }

    /// `✗ Suite / test(): message`, a failing test, keyed `Suite/test`.
    static func failure(_ line: String) -> (test: String, message: String)? {
        entry(line).flatMap(test(in:))
    }

    /// `Suite / test(): message`, the part of a failing test's line after its `✗`.
    static func test(in entry: String) -> (test: String, message: String)? {
        entry.firstMatch(of: #/^(.+?) \/ (\S+?): (.*)$/#).map { (key($0.1, $0.2), String($0.3)) }
    }

    /// `    /path/File.swift:12`, the line after a failure or an error that says where it happened.
    static func location(_ line: String) -> (path: String, line: String)? {
        line.firstMatch(of: #/^\s+(\/\S+):(\d+)\s*$/#).map { (String($0.1), String($0.2)) }
    }

    /// `⏭️ Suite/test() (0.000s)`, a skipped test, keyed `Suite/test`.
    static func skipped(_ line: String) -> String? {
        line.firstMatch(of: #/^\s*⏭\x{FE0F}? (\S+?)\/(\S+?) \(/#.matchingSemantics(.unicodeScalar)).map { key($0.1, $0.2) }
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
    static func counts(in text: String) -> (failed: Int, passed: Int, skipped: Int)? {
        text.firstMatch(of: #/❌ (\d+) tests? failed, (\d+) passed, (\d+) skipped/#).map { (Int($0.1) ?? 0, Int($0.2) ?? 0, Int($0.3) ?? 0) }
    }

    /// How many tests the summary line, passing or failing, counts as skipped.
    static func skippedCount(in text: String) -> Int {
        text.firstMatch(of: #/(?m)^(?:❌|✅) \d+ tests? .*?(\d+) skipped/#).flatMap { Int($0.1) } ?? 0
    }
}
