import Foundation

/// Adds what a result bundle knows to a failing MobileBuildMCP test run's text: each failure's
/// location, a crash's exception and frames, the images a failed test attached, a pointer to `look`
/// under a failed UI test, and each skipped test's reason, including skipped tests the text leaves out.
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
        /// Tests run more than once: their failures are listed once, the first, with how many runs failed.
        var repeated: Set<TestID> = []
        var skipped: [TestID: [String]] = [:]
        /// Skipped tests the text leaves out, written at the end of its Test Results list.
        var unlisted: [String] = []

        var isEmpty: Bool { failures.isEmpty && skipped.values.allSatisfy(\.isEmpty) && unlisted.isEmpty }
    }

    /// Writes the notes: a failure's go after it and its location line, once though the text lists a test twice, a
    /// skipped test's after its line. A repeated test's later failures, one per failed run, are left out, and the
    /// failures' heading counts those listed. Nil when none of them has a place in the text.
    static func annotate(_ text: MobileText, with notes: Notes) -> MobileText? {
        let lines = text.lines
        var out: [MobileText.Line] = []
        var noted: Set<TestID> = []
        // Where each repeated test's first failure is placed: a later one there is another run's, one elsewhere its own.
        var placed: [TestID: String] = [:]
        var added = false
        var dropped = 0
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
            if let failing = line.failing {
                // A failure is its line and, when the text places it, the location line after it.
                let span = text.location(after: index) == nil ? 1 : 2
                let place = text.location(after: index).map { "\($0.path):\($0.line)" } ?? ""
                if notes.repeated.contains(failing.test), let first = placed[failing.test], first == place {
                    // A later run's failure of a repeated test goes, with the blank line before it.
                    if out.last?.isBlank == true { out.removeLast() }
                    dropped += 1
                    added = true
                } else {
                    out += lines[index..<index + span]
                    if placed[failing.test] == nil { placed[failing.test] = place }
                    if noted.insert(failing.test).inserted { add(notes.failures[failing.test] ?? []) }
                }
                index += span
                continue
            }
            out.append(line)
            if case let .skipped(test?) = line.kind {
                add(notes.skipped[test] ?? [])
            }
            index += 1
        }
        if dropped > 0, let heading = out.firstIndex(where: { $0.isHeading(.testFailures) }), let counted = MobileBuildMCPLine.failureCount(in: out[heading].text) {
            out[heading] = MobileText.Line(out[heading].text.replacingCharacters(in: counted.range, with: "Test Failures (\(counted.count - dropped)):"))
        }
        return added ? MobileText(lines: out) : nil
    }

    /// What a failed test's image lines begin with, which the routing rules name.
    static let imageLabel = "image:"

    /// What the line under a failed UI test sending Claude to `look` begins with.
    static let lookLabel = "look:"

    /// The line sending Claude to `look` on this run's bundle, so a later run doesn't stand in for it. A test in a nested
    /// suite is named as the bundle names it, `()` and all, so its suite's `/` isn't read as a target's.
    static func lookLine(_ test: TestID, bundle: String) -> String {
        let named = test.shown.count(where: { $0 == "/" }) > 1 ? test.xcresultID : test.shown
        return "      \(lookLabel) the steps leading to the failure and the screen at it, with the `look` tool or `xcrew look \(named) --bundle \(bundle)`"
    }

    /// The text with its notes, and each failed test's images, for the failures pane.
    struct Added {
        let text: MobileText
        let images: [TestID: FailureImages]
    }

    /// The failing run's text with what the result bundle adds; nil when it adds nothing. With `imagesFolder`, each failed
    /// test's images are kept there, and runs kept there too long are removed.
    static func adding(to text: MobileText, from bundle: ResultBundle, keepingImagesIn imagesFolder: URL? = nil, repetitions repeatedTests: [ResultBundle.Repeated] = []) async -> Added? {
        var order: [TestID] = []
        var located: Set<TestID> = []
        var crashed: Set<TestID> = []
        for (index, line) in text.lines.enumerated() {
            guard let failing = line.failing else { continue }
            if !order.contains(failing.test) { order.append(failing.test) }
            if text.location(after: index) != nil { located.insert(failing.test) }
            if isCrash(failing.message) { crashed.insert(failing.test) }
        }
        // A test the text doesn't place, or that crashed, is looked up for that; the first failed tests for their images too.
        let detailed = Set(order.filter { !located.contains($0) || crashed.contains($0) }.prefix(mostLookups))
        let imaged = Set(imagesFolder == nil ? [] : order.prefix(mostLookups))
        let lookups = order.filter { detailed.contains($0) || imaged.contains($0) }
        let listedSkips = text.lines.compactMap { line -> TestID? in
            if case let .skipped(test) = line.kind { return test }
            return nil
        }
        let isSkipping = text.skippedCount > 0 || !listedSkips.isEmpty
        // A repeated run's tests, from its test list, which skips read too: how many runs each failed.
        let repetitions = repeatedTests.filter { $0.failed > 0 }
        guard !lookups.isEmpty || isSkipping || !repetitions.isEmpty else { return nil }
        // A Swift runtime error stops the process before XCTest records a message, so the run lists it under Errors, once
        // plainly and once with the xctest log's prefix. With one crashed test, it's that test's.
        let crashError = crashed.count == 1 ? text.reportedErrors.compactMap { MobileBuildMCPLine.runtimeError($0.message) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } } : []

        if let imagesFolder, !lookups.isEmpty { FailureImages.prune(in: imagesFolder) }
        var notes = Notes()
        var images: [TestID: FailureImages] = [:]
        // Each test's lookups are their own xcresulttool calls, so a few run side by side.
        notes.failures = await withTaskGroup(of: (TestID, [String], FailureImages?).self) { group in
            var pending = lookups.makeIterator()
            var found: [TestID: [String]] = [:]
            func lookUpNext() {
                guard let test = pending.next() else { return }
                let isLocated = !detailed.contains(test) || located.contains(test), isCrashed = detailed.contains(test) && crashed.contains(test)
                let keepsImages = imaged.contains(test) ? imagesFolder : nil
                group.addTask {
                    var added: [String] = []
                    let crash = isCrashed ? await bundle.crash(of: test) : nil
                    // Where the bundle places the failure, or for a crash, the crash log's frame in the test's own code.
                    if !isLocated, let location = ResultBundle.sourceLocation(details: await bundle.details(of: test)) ?? crash?.location {
                        added.append("    \(location)")
                    }
                    if isCrashed {
                        let summary = crash?.summary ?? [noCrashLog]
                        // The error goes under the exception's line, or heads the frames when the log names no exception.
                        let headed = summary.first?.hasPrefix("crashed:") == true ? 1 : 0
                        added += (Array(summary.prefix(headed)) + crashError + summary.dropFirst(headed)).map { "      \($0)" }
                    }
                    // One export for both: the test's images, and whether it kept a screen recording, as a UI test does.
                    let (attached, recorded) = if let keepsImages {
                        await bundle.attachments(of: test, onlyFailures: false) { export in
                            (FailureImages.keep(of: test, from: export, in: bundle.runFolder(in: keepsImages)),
                             FailureImages.attachments(of: test, in: export).contains { FailureScreen.isRecording($0["suggestedHumanReadableName"] as? String ?? "") })
                        }
                    } else {
                        (FailureImages?.none, false)
                    }
                    if let attached { added += attached.shown.map { "      \(imageLabel) \($0)" } + (attached.more.map { ["      \($0)"] } ?? []) }
                    if recorded { added.append(lookLine(test, bundle: bundle.path)) }
                    return (test, added, attached)
                }
            }
            for _ in 0..<mostAtOnce { lookUpNext() }
            // As each lookup finishes, the next one starts.
            while let (test, added, attached) = await group.next() {
                if !added.isEmpty { found[test] = added }
                if let attached { images[test] = attached }
                lookUpNext()
            }
            return found
        }
        for repeated in repetitions {
            let test = TestID(xcresultID: repeated.test)
            notes.repeated.insert(test)
            notes.failures[test, default: []].append("      failed \(repeated.failed) of \(repeated.runs) runs")
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
        guard !notes.isEmpty, let annotated = annotate(text, with: notes) else { return nil }
        return Added(text: annotated, images: images)
    }
}
