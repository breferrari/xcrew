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
        let milliseconds = ToolOutput.milliseconds(value)
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
        var failures: [TestID: [String]] = [:]
        var skipped: [TestID: [String]] = [:]
        /// Skipped tests the text leaves out, written at the end of its Test Results list.
        var unlisted: [String] = []

        var isEmpty: Bool { failures.isEmpty && skipped.values.allSatisfy(\.isEmpty) && unlisted.isEmpty }
    }

    /// Writes the notes: a failure's go after it and its location line, a skipped test's after its
    /// line. Nil when none of them has a place in the text.
    static func annotate(_ text: MobileText, with notes: Notes) -> MobileText? {
        let lines = text.lines
        var out: [MobileText.Line] = []
        var added = false
        // A note can span lines, a skip reason the test wrote over several; each is read as its own.
        func add(_ notes: [String]) {
            let split = notes.flatMap { $0.components(separatedBy: "\n") }.map(MobileText.Line.init)
            added = added || !split.isEmpty
            out += split
        }
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.isSummary, !notes.unlisted.isEmpty {
                let blank = out.last?.isBlank == true ? out.removeLast() : nil
                add(notes.unlisted)
                if let blank { out.append(blank) }
            }
            out.append(line)
            if let failing = line.failing {
                if text.location(after: index) != nil {
                    index += 1
                    out.append(lines[index])
                }
                add(notes.failures[failing.test] ?? [])
            } else if case let .skipped(test?) = line.kind {
                add(notes.skipped[test] ?? [])
            }
            index += 1
        }
        return added ? MobileText(lines: out) : nil
    }

    /// The failing run's text with what the result bundle adds; nil when it adds nothing.
    static func adding(to text: MobileText, from bundle: ResultBundle) async -> MobileText? {
        var order: [TestID] = []
        var located: Set<TestID> = []
        var crashed: Set<TestID> = []
        for (index, line) in text.lines.enumerated() {
            guard let failing = line.failing else { continue }
            if !order.contains(failing.test) { order.append(failing.test) }
            if text.location(after: index) != nil { located.insert(failing.test) }
            if isCrash(failing.message) { crashed.insert(failing.test) }
        }
        let lookups = order.filter { !located.contains($0) || crashed.contains($0) }.prefix(mostLookups)
        let listedSkips = text.lines.compactMap { line -> TestID? in
            if case let .skipped(test) = line.kind { return test }
            return nil
        }
        let isSkipping = text.skippedCount > 0 || !listedSkips.isEmpty
        guard !lookups.isEmpty || isSkipping else { return nil }

        var notes = Notes()
        // Each test's lookups are their own xcresulttool calls, so a few run side by side.
        notes.failures = await withTaskGroup(of: (TestID, [String]).self) { group in
            var pending = lookups.makeIterator()
            var found: [TestID: [String]] = [:]
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
            let reason = { (skip: ResultBundle.Skip) in skip.reason.map { [MobileBuildMCPLine.skipReason($0)] } ?? [] }
            var unlisted = 0
            for (test, skip) in await bundle.skips() {
                if listed.contains(test) {
                    notes.skipped[test] = reason(skip)
                } else if unlisted < mostLookups {
                    unlisted += 1
                    notes.unlisted += ["  ⏭️ \(test.xcresultID) (\(seconds(skip.seconds))s)"] + reason(skip)
                }
            }
        }
        return notes.isEmpty ? nil : annotate(text, with: notes)
    }
}
