import Foundation

extension ToolOutput {
    /// Passing tests listed past this many are counted instead: a failing run's list is what pushes it over the limit.
    static let passingListLimit = 20

    /// A MobileBuildMCP test result without its per-test list, which is nearly all of a large run's
    /// result (127 of 130 KB for 959 tests): the summary, counts, failures and artifacts stay, and the
    /// list is pointed to in `savedPath`. Nil for anything else.
    public func compactTestResult(savedPath: String) -> String? {
        guard var json = Self.object(text), json["schema"] as? String == "mobilebuildmcp.output.test-result",
              var data = json["data"] as? [String: Any], data["testCases"] is [Any]
        else { return nil }
        // No count of its own: the list can be one short of the summary's counts, which come from the result bundle.
        data["testCases"] = "per-test list left out to keep this result short; the counts above are complete, and the full result is in \(savedPath)"
        json["data"] = data
        guard let encoded = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(decoding: encoded, as: UTF8.self)
    }

    /// MobileBuildMCP's text for a failing test run, with `showTestTiming` on, lists every passing test
    /// under `Test Results:`. This keeps the failures, the failing and skipped tests' lines and the
    /// summary, and counts the passing ones. Nil when the list is short or the text is another shape.
    public var compactTestText: String? {
        guard text.hasPrefix("🧪 Test") else { return nil }
        let lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: "Test Results:") else { return nil }
        // The list runs to the summary line; a blank line inside it is where Claude Code cut a long one.
        let summary = lines.indices.first { $0 > start && lines[$0].contains(#/^(❌|✅) \d+ tests? /#) }
        var end = summary ?? start + 1
        if summary == nil { while end < lines.count, !lines[end].trimmingCharacters(in: .whitespaces).isEmpty { end += 1 } }
        while end > start + 1, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
        let section = lines[(start + 1)..<end]
        let listed = section.filter { $0.drop { $0 == " " }.hasPrefix("✅") }.count
        guard listed > Self.passingListLimit else { return nil }
        // The summary's count, since Claude Code may already have cut the middle of a long list.
        let passed = text.firstMatch(of: #/❌ \d+ tests? failed, (\d+) passed/#).flatMap { Int($0.1) } ?? listed
        // Failing tests are listed in full under Test Failures, while this list's ❌ lines come from the
        // parallel runners' log and can miss some, so only skipped tests (⏭️) keep their lines here.
        let listedAbove = lines.contains { $0.hasPrefix("Test Failures") }
        // A skipped test's line keeps the `skipped: <reason>` line the result bundle adds under it.
        let kept = section.filter { $0.unicodeScalars.contains("⏭") || $0.contains(#/^\s+skipped: /#) || (!listedAbove && $0.contains("❌")) }
        let note = listedAbove ? "  (\(passed) passing tests left out; failing tests are listed in full above)" : "  (\(passed) passing tests left out)"
        return (lines[...start] + [note] + kept + lines[end...]).joined(separator: "\n")
    }

    /// MobileBuildMCP lists a compile error twice: the message, and the compiler's caret line
    /// (`✗ |   \`- error: …`) as an error of its own. This drops the caret line and corrects the count.
    public var cleanBuildText: String? {
        var kept: [String] = []
        var dropped = 0
        for line in text.components(separatedBy: "\n") {
            if line.contains(#/^\s*✗ \|/#) {
                dropped += 1
                if kept.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { kept.removeLast() }
                continue
            }
            kept.append(line)
        }
        guard dropped > 0 else { return nil }
        let joined = kept.joined(separator: "\n")
        guard let errors = joined.firstMatch(of: #/(?m)^Errors \((\d+)\):/#), let count = Int(errors.1) else { return joined }
        return joined.replacingCharacters(in: errors.range, with: "Errors (\(max(1, count - dropped))):")
    }
}
