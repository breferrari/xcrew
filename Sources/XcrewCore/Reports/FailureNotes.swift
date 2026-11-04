import Foundation

/// Adds what a result bundle knows to a failing MobileBuildMCP test run's text: each failure's
/// location, a crash's exception and frames, the images a failed test attached, a pointer to `look`
/// under a failed UI test, and each skipped test's reason, including skipped tests the text leaves out.
public enum FailureNotes {
    /// At most this many tests are looked up at once: each is one or two xcresulttool processes on the same bundle, which
    /// a crowd of them only slows. Every test is looked up; this sets how many at a time.
    static let mostAtOnce = 4

    /// `0.006`, as MobileBuildMCP writes a test's time: three decimals, whatever the Mac's locale.
    static func seconds(_ value: Double) -> String {
        let milliseconds = ToolOutput.milliseconds(value)
        let fraction = String(milliseconds % 1000)
        return "\(milliseconds / 1000).\(String(repeating: "0", count: 3 - fraction.count))\(fraction)"
    }

    /// Under a crash whose run attached no crash log, so Claude knows why there are no frames.
    public static let noCrashLog = "no crash log came with this run; running the test alone, without parallel testing, may attach one"
    /// The same, under a crash in a run of that one test, so it names what running it alone didn't try: running it
    /// without parallel testing, under which each runner is on a clone of the simulator (docs/findings.md).
    public static let noCrashLogAlone = "no crash log came with this run, though it ran this test alone; under parallel testing each runner is on a clone of the simulator, and `-parallel-testing-enabled NO` in `extraArgs` turns it off"

    /// Whether the run's one crashed test ran alone: its bundle counts one test, expected failures included, which
    /// MobileBuildMCP's summary leaves out, and its text discovered no more, as a crash can keep the rest from running.
    static func ranAlone(discovered: Int?, bundle: ResultBundle) async -> Bool {
        guard (discovered ?? 1) <= 1 else { return false }
        return ResultBundle.counts(summary: await bundle.summary())?.ran == 1
    }

    /// MobileBuildMCP words a crash `Crash: xctest at …` when a crash log came with the run, and
    /// `Test crashed with signal …` when none did.
    static func isCrash(_ message: String) -> Bool {
        message.hasPrefix("Crash:") || message.hasPrefix("Test crashed with signal")
    }

    /// A failing line of a test: the test's own failure, or a crash, each with its own notes, so a test with both has the
    /// crash's under the crash.
    struct FailedLine: Hashable, Sendable {
        let test: TestID
        let isCrash: Bool
    }

    struct Notes: Sendable {
        var failures: [FailedLine: [String]] = [:]
        /// Tests run more than once: their failures are listed once for each kind, the first, with how many runs failed.
        var repeated: Set<TestID> = []
        var skipped: [TestID: [String]] = [:]
        /// Skipped tests the text leaves out, written at the end of its Test Results list.
        var unlisted: [String] = []

        var isEmpty: Bool { failures.isEmpty && skipped.values.allSatisfy(\.isEmpty) && unlisted.isEmpty }
    }

    /// Writes the notes: a failure's go after it and its location line, once for each kind of a test's failure, its own
    /// and a crash, though the text lists one twice; a skipped test's after its line. A repeated test's later failures of
    /// one kind, one per failed run, are left out, and the failures' heading counts those listed. Nil when none of them
    /// has a place in the text.
    static func annotate(_ text: MobileText, with notes: Notes) -> MobileText? {
        let lines = text.lines
        var out: [MobileText.Line] = []
        var noted: Set<FailedLine> = []
        // Where each repeated test's first failure is placed: a later one there is another run's, one elsewhere its own.
        var placed: [FailedLine: String] = [:]
        var added = false
        var dropped = 0
        // Bare places the bundle's whole path for the same file and line stands for, by index.
        var replacedPlaces: Set<Int> = []
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
                let key = FailedLine(test: failing.test, isCrash: isCrash(failing.message))
                if notes.repeated.contains(failing.test), let first = placed[key], first == place {
                    // A later run's failure of a repeated test goes, with the blank line before it.
                    if out.last?.isBlank == true { out.removeLast() }
                    dropped += 1
                    added = true
                } else {
                    out += lines[index..<index + span]
                    if placed[key] == nil { placed[key] = place }
                    if noted.insert(key).inserted {
                        let entryNotes = notes.failures[key] ?? []
                        add(entryNotes)
                        replacedPlaces.formUnion(barePlaces(standingFor: entryNotes.first, below: index + span, in: lines))
                    }
                }
                index += span
                continue
            }
            if replacedPlaces.contains(index) {
                index += 1
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

    /// The lines of the entry from `start` that are a bare place, `File.swift:29`, of the file and line `note`, a whole
    /// path the bundle gave, names: that path stands for them. None when the note is no place.
    static func barePlaces(standingFor note: String?, below start: Int, in lines: [MobileText.Line]) -> [Int] {
        guard let note, let place = MobileText.Line(note).location else { return [] }
        let bare = "\(ToolOutput.basename(place.path)):\(place.line)"
        var standing: [Int] = []
        var index = start
        while index < lines.count, lines[index].failing == nil, !lines[index].isBlank {
            if lines[index].location == nil, lines[index].text.trimmingCharacters(in: .whitespaces) == bare { standing.append(index) }
            index += 1
        }
        return standing
    }

    /// What a failed test's image lines begin with, which the routing rules name.
    static let imageLabel = "image:"

    /// What the line under a failed UI test sending Claude to `look` begins with.
    static let lookLabel = "look:"

    /// The line sending Claude to `look` on this run's bundle, so a later run doesn't stand in for it, the test and the
    /// bundle each one word of the command.
    static func lookLine(_ test: TestID, bundle: String) -> String {
        "      \(lookLabel) the steps leading to the failure and the screen at it, with the `look` tool or `\(test.lookCommand(bundle: bundle))`"
    }

    /// The text with its notes, and each failed test's images, for the failures pane.
    struct Added {
        let text: MobileText
        let images: [TestID: FailureImages]
    }

    /// The failing run's text with what the result bundle adds; nil when it adds nothing. With `images`, each failed
    /// test's images are kept in its folder, and the runs kept there longer than `FailureImages.keptDays` before its `now`
    /// are removed. The skips are read from the bundle's own test list, after the failures are looked up. `bundleIDs` and
    /// `labels` are as `lookingUp` takes them.
    static func adding(to text: MobileText, from bundle: ResultBundle, keepingImagesIn images: (folder: URL, now: Date)? = nil, repetitions: [ResultBundle.Repeated] = [], bundleIDs: [TestID: TestLookup.Resolution] = [:], crashCases: [TestID: TestID] = [:], labels: [TestID: String] = [:]) async -> Added? {
        guard let pending = await lookingUp(text, from: bundle, keepingImagesIn: images, repetitions: repetitions, bundleIDs: bundleIDs, crashCases: crashCases, labels: labels) else { return nil }
        return pending.adding(skips: pending.readsSkips ? ResultBundle.skippedTests(listing: TestList(await bundle.tests())) : [])
    }

    /// What `adding` finds before the run's skips: each failed test's lookups and its repeated runs, the failures read
    /// first.
    struct Pending: Sendable {
        let text: MobileText
        let notes: Notes
        let images: [TestID: FailureImages]
        /// The skipped tests the text lists, by name.
        let listedSkips: [TestID]
        /// Whether the run's skips are read from its test list: its text counts or lists a skipped test.
        let readsSkips: Bool

        /// The text with every note, `skips` the run's skipped tests from its test list: a listed one's reason under its
        /// line, each the text leaves out added; nil when it adds nothing.
        func adding(skips: [(test: TestID, skip: ResultBundle.Skip)]) -> Added? {
            var notes = notes
            let listed = Set(listedSkips)
            let reason = { (skip: ResultBundle.Skip) in skip.reason.map { [MobileBuildMCPLine.skipReason($0)] } ?? [] }
            for (test, skip) in skips {
                if listed.contains(test) {
                    notes.skipped[test] = reason(skip)
                } else {
                    notes.unlisted += ["  ⏭️ \(test.xcresultID) (\(seconds(skip.seconds))s)"] + reason(skip)
                }
            }
            guard !notes.isEmpty, let annotated = annotate(text, with: notes) else { return nil }
            return Added(text: annotated, images: images)
        }
    }

    /// The line under a failed test whose name ends several of the bundle's ids, `ids`: it's looked up under none.
    static func severalByThatName(_ ids: [TestID]) -> String {
        "the result bundle has more than one test by that name: \(candidates(ids))"
    }

    /// The bundle's tests a name can mean, five at most and the rest counted.
    static func candidates(_ ids: [TestID]) -> String {
        ResultBundle.joined(ids.map(\.shown), rest: "in the result bundle's test list")
    }

    /// The first step of `adding`: each failing line's lookups and its test's repeated runs. Nil when there's nothing to
    /// add and no skip to read. Each line is looked up under the bundle's id for its test in `bundleIDs`, by the name the
    /// text gives it, and its images are keyed by that id; one whose resolution is `.ambiguous` gets a line saying so. A
    /// test with a failure of its own and a crash has each one's notes under its own line, the crash's looked up under the
    /// `System Failures` case `crashCases` files it under, where the bundle keeps its log; a crash alone is looked up
    /// under its own id, as any test is. A test's `labels` entry goes under its first line's place, before its other
    /// notes.
    static func lookingUp(_ text: MobileText, from bundle: ResultBundle, keepingImagesIn images: (folder: URL, now: Date)? = nil, repetitions repeatedTests: [ResultBundle.Repeated] = [], bundleIDs: [TestID: TestLookup.Resolution] = [:], crashCases: [TestID: TestID] = [:], labels: [TestID: String] = [:]) async -> Pending? {
        let imagesFolder = images?.folder
        var order: [FailedLine] = []
        var located: Set<FailedLine> = []
        for (index, line) in text.lines.enumerated() {
            guard let failing = line.failing else { continue }
            let key = FailedLine(test: failing.test, isCrash: isCrash(failing.message))
            if !order.contains(key) { order.append(key) }
            if text.location(after: index) != nil { located.insert(key) }
        }
        let crashedCount = order.count(where: \.isCrash)
        var seen: Set<TestID> = []
        let firsts = Set(order.filter { seen.insert($0.test).inserted })
        // A line the text doesn't place, or a crash, is looked up for that; every failing line for its images too.
        let detailed = Set(order.filter { !located.contains($0) || $0.isCrash })
        let ambiguous = Set(order.filter { firsts.contains($0) && bundleIDs[$0.test]?.isAmbiguous == true })
        let lookups = order.filter { detailed.contains($0) || imagesFolder != nil || ambiguous.contains($0) || (firsts.contains($0) && labels[$0.test] != nil) }
        let listedSkips = text.lines.compactMap { line -> TestID? in
            if case let .skipped(test) = line.kind { return test }
            return nil
        }
        let readsSkips = text.skippedCount > 0 || !listedSkips.isEmpty
        // A repeated run's tests, from its test list: how many runs each failed.
        let repetitions = repeatedTests.filter { $0.failed > 0 }
        guard !lookups.isEmpty || readsSkips || !repetitions.isEmpty else { return nil }
        // A Swift runtime error stops the process before XCTest records a message, so the run lists it under Errors, once
        // plainly and once with the xctest log's prefix. With one crashed test, it's that test's.
        let crashError = crashedCount == 1 ? text.reportedErrors.compactMap { MobileBuildMCPLine.runtimeError($0.message) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } } : []

        let (oneCrashed, discovered) = (crashedCount == 1, text.discovered)
        if let images, !lookups.isEmpty { FailureImages.prune(in: images.folder, now: images.now) }
        var notes = Notes()
        var images: [TestID: FailureImages] = [:]
        // Each test's lookups are their own xcresulttool calls, so a few run side by side.
        notes.failures = await withTaskGroup(of: (FailedLine, TestID, [String], FailureImages?).self) { group in
            var pending = lookups.makeIterator()
            var found: [FailedLine: [String]] = [:]
            func lookUpNext() {
                guard let key = pending.next() else { return }
                let test = key.test
                let isLocated = !detailed.contains(key) || located.contains(key), isCrashed = key.isCrash && detailed.contains(key)
                let resolution = bundleIDs[test]
                let ownID = resolution?.found ?? test
                let crashID = key.isCrash && order.contains(FailedLine(test: test, isCrash: false)) ? crashCases[test] : nil
                let id = crashID ?? ownID
                let label = firsts.contains(key) ? labels[test] : nil
                let named = MobileBuildMCPLine.isProcessCrash(id.suite) ? test : id
                // A name the bundle can't pick a test by is said once, under the test's first line, and asked of no lookup.
                let isAmbiguous = resolution?.isAmbiguous == true && crashID == nil
                let severalNote = if ambiguous.contains(key), case let .ambiguous(ids)? = resolution { ["      \(Self.severalByThatName(ids))"] } else { [String]() }
                group.addTask {
                    if isAmbiguous { return (key, id, severalNote, nil) }
                    var added: [String] = []
                    var crash = isCrashed ? await bundle.crash(of: id, naming: named) : nil
                    if isCrashed, crash == nil, id != ownID, resolution?.isAmbiguous != true { crash = await bundle.crash(of: ownID, naming: named) }
                    // Where the bundle places the failure, or for a crash, the crash log's frame in the test's own code.
                    if !isLocated, let location = ResultBundle.sourceLocation(details: await bundle.details(of: id)) ?? crash?.location {
                        added.append("    \(location)")
                    }
                    added += severalNote
                    if let label { added.append("      \(label)") }
                    if isCrashed {
                        let alone = crash == nil && oneCrashed ? await ranAlone(discovered: discovered, bundle: bundle) : false
                        let summary = crash?.summary ?? [alone ? noCrashLogAlone : noCrashLog]
                        // The error goes under the exception's line, or heads the frames when the log names no exception.
                        let headed = summary.first?.hasPrefix("crashed:") == true ? 1 : 0
                        added += (Array(summary.prefix(headed)) + crashError + summary.dropFirst(headed)).map { "      \($0)" }
                    }
                    // One export for both: the test's images, and whether it kept a screen recording, as a UI test does.
                    let (attached, recorded) = if let imagesFolder {
                        await bundle.attachments(of: id, onlyFailures: false) { export in
                            (FailureImages.keep(of: id, from: export, in: bundle.runFolder(in: imagesFolder)),
                             FailureImages.attachments(of: id, in: export).contains { FailureScreen.isRecording($0["suggestedHumanReadableName"] as? String ?? "") })
                        }
                    } else {
                        (FailureImages?.none, false)
                    }
                    if let attached { added += attached.shown.map { "      \(imageLabel) \($0)" } + (attached.more.map { ["      \($0)"] } ?? []) }
                    if recorded { added.append(lookLine(named, bundle: bundle.path)) }
                    return (key, id, added, attached)
                }
            }
            for _ in 0..<mostAtOnce { lookUpNext() }
            // As each lookup finishes, the next one starts.
            while let (key, id, added, attached) = await group.next() {
                if !added.isEmpty { found[key] = added }
                if let attached { images[id] = attached }
                lookUpNext()
            }
            return found
        }
        if let imagesFolder, !images.isEmpty { FailureImages.record(bundle.runFolder(in: imagesFolder)) }
        let textNames = Dictionary(order.compactMap { line in bundleIDs[line.test]?.found.map { ($0, line.test) } }) { first, _ in first }
        for repeated in repetitions {
            let test = textNames[TestID(xcresultID: repeated.test)] ?? TestID(xcresultID: repeated.test)
            notes.repeated.insert(test)
            let line = order.first { $0.test == test } ?? FailedLine(test: test, isCrash: false)
            notes.failures[line, default: []].append("      failed \(repeated.failed) of \(repeated.runs) runs")
        }
        return Pending(text: text, notes: notes, images: images, listedSkips: listedSkips, readsSkips: readsSkips)
    }
}
