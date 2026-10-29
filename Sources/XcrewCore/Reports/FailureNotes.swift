import Foundation

/// Adds what a result bundle knows to a failing MobileBuildMCP test run's text: each failure's
/// location, a crash's exception and frames, and each skipped test's reason, including skipped
/// tests the text leaves out.
public enum FailureNotes {
    /// At most this many tests are looked up: past it, the first ones are enough to start from.
    static let mostLookups = 10
    /// At most this many tests are looked up at once: each is one or two xcresulttool processes on
    /// the same bundle, and a crowd of them on a busy Mac runs into their timeouts.
    static let mostAtOnce = 4

    /// `0.006`, as MobileBuildMCP writes a test's time: three decimals, whatever the Mac's locale.
    static func seconds(_ value: Double) -> String {
        let milliseconds = Int((value * 1000).rounded())
        let fraction = String(milliseconds % 1000)
        return "\(milliseconds / 1000).\(String(repeating: "0", count: 3 - fraction.count))\(fraction)"
    }

    /// Under a crash whose run attached no crash log, so Claude knows why there are no frames.
    public static let noCrashLog = "no crash log came with this run; running the test alone, without parallel testing, may attach one"

    /// MobileBuildMCP words a crash `Crash: xctest at …` when a crash log came with the run, and
    /// `Test crashed with signal …` when none did.
    static func isCrash(_ message: String) -> Bool {
        message.hasPrefix("Crash:") || message.hasPrefix("Test crashed with signal")
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
            if MobileBuildMCPLine.isSummary(line), !notes.unlisted.isEmpty {
                let blank = out.last?.trimmingCharacters(in: .whitespaces).isEmpty == true ? out.removeLast() : nil
                out += notes.unlisted
                if let blank { out.append(blank) }
            }
            out.append(line)
            if let failure = MobileBuildMCPLine.failure(line) {
                if index + 1 < lines.count, MobileBuildMCPLine.location(lines[index + 1]) != nil {
                    index += 1
                    out.append(lines[index])
                }
                out += notes.failures[failure.test] ?? []
            } else if let test = MobileBuildMCPLine.skipped(line) {
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
            guard let failure = MobileBuildMCPLine.failure(line) else { continue }
            if !order.contains(failure.test) { order.append(failure.test) }
            if index + 1 < lines.count, MobileBuildMCPLine.location(lines[index + 1]) != nil { located.insert(failure.test) }
            if isCrash(failure.message) { crashed.insert(failure.test) }
        }
        let lookups = order.filter { !located.contains($0) || crashed.contains($0) }.prefix(mostLookups)
        let listedSkips = lines.compactMap(MobileBuildMCPLine.skipped)
        let isSkipping = MobileBuildMCPLine.skippedCount(in: text) > 0 || !listedSkips.isEmpty
        guard !lookups.isEmpty || isSkipping else { return text }

        var notes = Notes()
        // Each test's lookups are their own xcresulttool calls, so a few run side by side.
        notes.failures = await withTaskGroup(of: (String, [String]).self) { group in
            var pending = lookups.makeIterator()
            var found: [String: [String]] = [:]
            func lookUpNext() {
                guard let test = pending.next() else { return }
                let isLocated = located.contains(test), isCrashed = crashed.contains(test)
                group.addTask {
                    var added: [String] = []
                    if !isLocated, let location = ResultBundle.sourceLocation(details: await bundle.details(of: test)) {
                        added.append("    \(location)")
                    }
                    if isCrashed { added += (await bundle.crash(of: test) ?? [noCrashLog]).map { "      \($0)" } }
                    return (test, added)
                }
            }
            for _ in 0..<mostAtOnce { lookUpNext() }
            // As each lookup finishes, the next one starts.
            while let (test, added) = await group.next() {
                if !added.isEmpty { found[test] = added }
                lookUpNext()
            }
            return found
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
