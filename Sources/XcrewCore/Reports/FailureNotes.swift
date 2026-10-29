import Foundation

/// Adds what a result bundle knows to a failing MobileBuildMCP test run's text: each failure's
/// location, a crash's exception and frames, and each skipped test's reason, including skipped
/// tests the text leaves out.
public enum FailureNotes {
    /// At most this many tests are looked up: past it, the first ones are enough to start from.
    static let mostLookups = 10

    /// A test as `Suite/test`: MobileBuildMCP lists one failure both with and without the `()`.
    static func key(_ suite: String, _ test: String) -> String {
        "\(suite)/\(test.hasSuffix("()") ? String(test.dropLast(2)) : test)"
    }

    /// `✗ Suite / test(): message`, as MobileBuildMCP lists a failing test.
    static func failure(_ line: String) -> (test: String, message: String)? {
        line.firstMatch(of: #/^\s*✗ (.+?) \/ (\S+?): (.*)$/#).map { (key(String($0.1), String($0.2)), String($0.3)) }
    }

    /// `⏭️ Suite/test() (0.000s)`, as it lists a skipped one.
    static func skipped(_ line: String) -> String? {
        // By scalar: `⏭️` is `⏭` and a variation selector, one character that a character-level match misses.
        line.firstMatch(of: #/^\s*⏭\x{FE0F}? (\S+?)\/(\S+?) \(/#.matchingSemantics(.unicodeScalar)).map { key(String($0.1), String($0.2)) }
    }

    /// `0.006`, as MobileBuildMCP writes a test's time: three decimals, whatever the Mac's locale.
    static func seconds(_ value: Double) -> String {
        let milliseconds = Int((value * 1000).rounded())
        let fraction = String(milliseconds % 1000)
        return "\(milliseconds / 1000).\(String(repeating: "0", count: 3 - fraction.count))\(fraction)"
    }

    static func isPath(_ line: String) -> Bool {
        line.contains(#/^\s+\/\S+:\d+\s*$/#)
    }

    static func isSummary(_ line: String) -> Bool {
        line.contains(#/^(❌|✅) \d+ tests? /#)
    }

    struct Notes {
        var failures: [String: [String]] = [:]
        var skipped: [String: [String]] = [:]
        /// Skipped tests the text leaves out, written at the end of its Test Results list.
        var unlisted: [String] = []

        var isEmpty: Bool { failures.isEmpty && skipped.values.allSatisfy(\.isEmpty) && unlisted.isEmpty }
    }

    /// Writes the notes: a failure's go after it and its location line, a skipped test's after its line.
    static func annotate(_ text: String, with notes: Notes) -> String {
        let lines = text.components(separatedBy: "\n")
        var out: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if isSummary(line), !notes.unlisted.isEmpty {
                let blank = out.last?.trimmingCharacters(in: .whitespaces).isEmpty == true ? out.removeLast() : nil
                out += notes.unlisted
                if let blank { out.append(blank) }
            }
            out.append(line)
            if let failure = failure(line) {
                if index + 1 < lines.count, isPath(lines[index + 1]) {
                    index += 1
                    out.append(lines[index])
                }
                out += notes.failures[failure.test] ?? []
            } else if let test = skipped(line) {
                out += notes.skipped[test] ?? []
            }
            index += 1
        }
        return out.joined(separator: "\n")
    }

    /// The failing run's text with what the result bundle adds, or the text as it was when it adds nothing.
    public static func adding(to text: String, from bundle: ResultBundle) async -> String {
        let lines = text.components(separatedBy: "\n")
        var order: [String] = []
        var located: Set<String> = []
        var crashed: Set<String> = []
        for (index, line) in lines.enumerated() {
            guard let failure = failure(line) else { continue }
            if !order.contains(failure.test) { order.append(failure.test) }
            if index + 1 < lines.count, isPath(lines[index + 1]) { located.insert(failure.test) }
            if failure.message.hasPrefix("Crash:") { crashed.insert(failure.test) }
        }
        let lookups = order.filter { !located.contains($0) || crashed.contains($0) }.prefix(mostLookups)
        let listedSkips = lines.compactMap(skipped)
        let skippedCount = text.firstMatch(of: #/(?m)^(?:❌|✅) \d+ tests? .*?(\d+) skipped/#).flatMap { Int($0.1) } ?? 0
        let isSkipping = skippedCount > 0 || !listedSkips.isEmpty
        guard !lookups.isEmpty || isSkipping else { return text }

        var notes = Notes()
        for test in lookups {
            var added: [String] = []
            if !located.contains(test), let location = ResultBundle.sourceLocation(details: await bundle.details(of: test)) {
                added.append("    \(location)")
            }
            if crashed.contains(test) { added += (await bundle.crash(of: test) ?? []).map { "      \($0)" } }
            if !added.isEmpty { notes.failures[test] = added }
        }
        if isSkipping {
            let listed = Set(listedSkips)
            let reason = { (skip: ResultBundle.Skip) in skip.reason.map { ["      skipped: \($0)"] } ?? [] }
            var unlisted = 0
            for (test, skip) in await bundle.skips() {
                if listed.contains(test) {
                    notes.skipped[test] = reason(skip)
                } else if unlisted < mostLookups {
                    unlisted += 1
                    notes.unlisted += ["  ⏭️ \(test)() (\(seconds(skip.seconds))s)"] + reason(skip)
                }
            }
        }
        return notes.isEmpty ? text : annotate(text, with: notes)
    }
}
