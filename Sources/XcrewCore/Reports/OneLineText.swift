import Foundation

/// MobileBuildMCP's build or test text as a failed background task's notification gives it: on one line, each run of line
/// breaks and indents a space (docs/findings.md, *A call moved to the background*), and maybe cut short. Its lines are
/// found again by MobileBuildMCP's own markers, so it reads as the text the server wrote, whatever its end.
enum OneLineText {
    /// Where a line of MobileBuildMCP's began: a section's heading, an error, warning, failure or test's line, the
    /// summary, the files under it and the next steps. `⏭️` is matched with its variation selector and without.
    static var marker: Regex<Substring> { #/ (?=(?:Errors|Warnings|Test Failures) \(\d+\):|Test Results:|Discovered \d+ test\(s\):|Raw Output:|Next steps:|✗ |⚠ |✅ |❌ |⏭️|⏭|└ Files:|└── |├── )/# }
    /// A section whose entries each follow a blank line: an error, warning or failure, with its place below it.
    static var spacedHeading: Regex<Substring> { #/^(?:Errors|Warnings|Test Failures) \(\d+\):$/# }
    /// The list of discovered tests, each test's id on a line of its own, and what follows it on the same line.
    static var discovered: Regex<(Substring, Substring, Substring)> { #/^(Discovered \d+ test\(s\):) ?(.*)$/# }
    /// One discovered test's id, or the count of those left out, `(...and 1 more)`.
    static var discoveredTest: Regex<Substring> { #/\(\.\.\.and \d+ more\)|\S+/# }
    /// xcodebuild's own output, whose lines have no marker to find them by: it stays on one.
    static var rawOutput: Regex<(Substring, Substring)> { #/^Raw Output: ?(.*)$/# }
    /// The calls MobileBuildMCP suggests after a build, `Next steps:` and each numbered on its own line.
    static var nextSteps: Regex<(Substring, Substring)> { #/^Next steps: ?(.*)$/# }
    /// Where a numbered step begins.
    static var step: Regex<Substring> { #/ (?=\d+\. )/# }
    /// The summary under the sections, `❌ 2 tests failed, 1 passed (⏱️ 14.2s)` or `✅ Test succeeded.`.
    static var summary: Regex<Substring> { #/^[✅❌] (?:Test |Build |\d+ tests? )/# }
    /// An error's, warning's or failure's place at its end, `/…/File.swift:99`, which MobileBuildMCP puts on a line below.
    /// A place whose path holds a space reads from its last.
    static var place: Regex<(Substring, Substring, Substring)> { #/^(.+) (\S*[\/.]\S*:\d+)$/# }

    /// `text` on the lines MobileBuildMCP wrote it on; nil when it's already on several, or isn't a build's or test
    /// run's text.
    static func unfolded(_ text: String) -> String? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.contains("\n"), line.hasPrefix("🧪 ") || line.hasPrefix("🔨 ") else { return nil }
        var parts: [Substring] = []
        var start = line.startIndex
        for match in line.matches(of: marker) {
            parts.append(line[start..<match.range.lowerBound])
            start = match.range.upperBound
        }
        parts.append(line[start...])
        var lines = "\n" + parts[0]
        var spaced = false
        var filesRoot = true
        for part in parts.dropFirst() {
            if part.wholeMatch(of: spacedHeading) != nil || part == "Test Results:" {
                spaced = part != "Test Results:"
                lines += "\n\n" + part
            } else if let list = part.wholeMatch(of: discovered) {
                lines += "\n\n" + list.1 + list.2.matches(of: discoveredTest).map { "\n   " + $0.output }.joined()
            } else if let steps = part.wholeMatch(of: nextSteps) {
                lines += "\n\nNext steps:" + steps.1.split(separator: step).map { "\n" + $0 }.joined()
            } else if let raw = part.wholeMatch(of: rawOutput) {
                lines += "\n\nRaw Output:\n\n  " + raw.1
            } else if part.firstMatch(of: summary) != nil {
                lines += "\n\n" + part
            } else if part.hasPrefix("└ Files:") {
                lines += "\n  " + part
            } else if part.hasPrefix("└── ") || part.hasPrefix("├── ") {
                lines += (filesRoot ? "\n     " : "\n         ") + part
                filesRoot = false
            } else {
                let placed = part.hasPrefix("✗ ") || part.hasPrefix("⚠ ") ? part.wholeMatch(of: place) : nil
                lines += (spaced ? "\n\n  " : "\n  ") + (placed.map { $0.1 + "\n    " + $0.2 } ?? part)
            }
        }
        return lines + "\n"
    }
}
