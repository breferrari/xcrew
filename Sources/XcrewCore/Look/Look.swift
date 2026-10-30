import Foundation

/// What a run kept about the moment each failed UI test failed, for Claude to look at before changing a test or a view:
/// per failed run, its configuration and device, the steps before the failure, the failure, and the screen at it.
public enum Look {
    /// Failed UI tests shown when none is named; the rest are named for a later look.
    static let mostTests = 3
    /// Failed tests whose steps are read, when none is named, for whether they're UI tests.
    static let mostScanned = 40
    /// Elements of a hierarchy shown under a failed run; the rest are counted, with the file that holds them all.
    static let mostElements = 30

    /// What `look` says about one test in `bundle`, or, with none named, about its failed UI tests: those whose failed
    /// runs kept a screen recording. Screens are kept under `folder`, in a folder per run, and runs kept there too long
    /// are removed.
    public static func report(bundle: ResultBundle, test: TestID?, keptIn folder: URL) async -> String {
        let name = URL(fileURLWithPath: bundle.path).lastPathComponent
        let run = bundle.runFolder(in: folder)
        FailureImages.prune(in: folder)
        if let test {
            guard let read = FailedRun.read(activities: await bundle.activities(of: test), listing: await bundle.tests(), of: test) else {
                return "xcrew: couldn't read \(test.shown)'s steps in \(name); xcrun xcresulttool get test-results activities --test-id \(test.xcresultID) --path \(bundle.path) says why"
            }
            return await look(at: test, runs: read.failed, passed: read.passed, in: bundle, named: name, keptIn: run) ?? "xcrew: \(test.shown) didn't fail in \(name)"
        }
        guard let failed = await bundle.failedTests() else {
            return "xcrew: couldn't read the tests in \(name); xcrun xcresulttool get test-results tests --path \(bundle.path) says why"
        }
        guard !failed.isEmpty else { return "xcrew: nothing failed in \(name)" }
        // A few at a time, in the listing's order, until enough UI tests are found: a unit test costs one read of its steps.
        let scanned = Array(failed.prefix(mostScanned))
        var shown: [String] = []
        var unshown: [TestID] = []
        var next = 0
        while next < scanned.count, shown.count < mostTests {
            let batch = Array(scanned[next..<min(next + FailureNotes.mostAtOnce, scanned.count)])
            next += batch.count
            let looked = await withTaskGroup(of: (Int, String?).self) { group in
                for (index, test) in batch.enumerated() {
                    group.addTask {
                        guard let read = FailedRun.read(activities: await bundle.activities(of: test), listing: await bundle.tests(), of: test),
                              read.failed.contains(where: \.hasRecording)
                        else { return (index, nil) }
                        return (index, await look(at: test, runs: read.failed, passed: read.passed, in: bundle, named: name, keptIn: run))
                    }
                }
                var found = [String?](repeating: nil, count: batch.count)
                for await (index, text) in group { found[index] = text }
                return found
            }
            for (test, text) in zip(batch, looked) {
                guard let text else { continue }
                if shown.count < mostTests { shown.append(text) } else { unshown.append(test) }
            }
        }
        guard !shown.isEmpty else {
            let among = failed.count > scanned.count ? "none of the first \(scanned.count) failed tests" : "no failed test"
            return "xcrew: \(among) in \(name) kept a screen recording, as a UI test's failed run does; xcrew look <Suite/test> shows one test's steps"
        }
        unshown += failed.dropFirst(next)
        let more = unshown.isEmpty ? [] : ["and \(unshown.count) more failed \(unshown.count == 1 ? "test" : "tests")" + ResultBundle.listed(unshown.map { "xcrew look \($0.shown)" })]
        return (shown + more).joined(separator: "\n")
    }

    /// One test's failed runs, each with its steps, failure and screen, then where it passed; nil when none failed. A
    /// run's screen is numbered when the test failed more than once on its device and configuration, as a repeated run
    /// does.
    static func look(at test: TestID, runs: [FailedRun], passed: [String], in bundle: ResultBundle, named name: String, keptIn run: URL) async -> String? {
        guard !runs.isEmpty else { return nil }
        // Numbered by the label the kept file is named by: parallel clones of one simulator share it.
        let numbers = runs.indices.map { index in
            runs.filter { $0.label == runs[index].label }.count > 1 ? runs[..<index].filter { $0.label == runs[index].label }.count + 1 : nil
        }
        // Every attachment, and only for runs that attached any, as a unit test's don't: the hierarchy is told by its
        // content, and the recordings make up nearly all of an export (docs/findings.md).
        let kept: [(screen: FailureScreen?, hierarchy: FailureHierarchy?)] = if runs.contains(where: { !$0.attachments.isEmpty }) {
            await bundle.attachments(of: test, onlyFailures: false) { export in
                let files = files(in: export)
                var kept: [(screen: FailureScreen?, hierarchy: FailureHierarchy?)] = []
                for (failed, number) in zip(runs, numbers) {
                    kept.append((await FailureScreen.keep(of: test, run: failed, number: number, files: files, in: run), FailureHierarchy.keep(of: test, run: failed, number: number, files: files, in: run)))
                }
                return kept
            }
        } else {
            runs.map { _ in (nil, nil) }
        }
        var lines = ["xcrew look: \(test.shown), in \(name)"]
        for (failed, found) in zip(runs, kept) {
            lines.append("  " + failed.label)
            lines += failed.steps.map { "    \(firstLine($0))" }
            lines.append("    ✗ \(firstLine(failed.failure))")
            guard !failed.attachments.isEmpty else { continue }
            lines.append("    " + screenLine(found.screen, recorded: failed.hasRecording))
            lines += hierarchyLines(found.hierarchy, query: UIQuery(failure: failed.failure, steps: failed.steps)).map { "    \($0)" }
        }
        if !passed.isEmpty { lines.append("  passed under: " + passed.joined(separator: "; ")) }
        return lines.joined(separator: "\n")
    }

    static func screenLine(_ screen: FailureScreen?, recorded: Bool) -> String {
        guard let screen else { return recorded ? "screen: none; its recording couldn't be read" : "screen: none; the run kept no screen recording" }
        return screen.secondsBefore < 1 ? "screen: \(screen.path)" : "screen: \(screen.path) (\(Int(screen.secondsBefore.rounded())) s before the failure)"
    }

    /// The elements on screen at the failure, the query's marked or named missing; or, for a hierarchy in a shape xcrew
    /// doesn't read, its text as XCTest wrote it.
    static func hierarchyLines(_ kept: FailureHierarchy?, query: UIQuery?) -> [String] {
        guard let kept else { return ["on screen: no hierarchy kept; XCTest attaches one when a query fails"] }
        let more = { (count: Int) in count > 0 ? ["  and \(count) more in \(kept.path)"] : [] }
        switch kept.content {
        case let .asWritten(text):
            let raw = text.split(separator: "\n").map(String.init)
            return ["on screen, as XCTest wrote it:"] + raw.prefix(mostElements).map { "  \($0)" } + more(raw.count - mostElements)
        case let .read(hierarchy):
            let shown = hierarchy.lines(query: query, most: mostElements)
            let head = if let query, !shown.found { "on screen, nothing the query's \"\(query.text)\" \(query.type) matches:" } else { "on screen:" }
            return [head] + shown.lines.map { "  \($0)" } + more(shown.more)
        }
    }

    /// An export's files by the attachment id that names each, its extension dropped.
    static func files(in export: URL) -> [String: URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: export.path)) ?? []
        return Dictionary(names.map { (URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent, export.appending(path: $0)) }) { first, _ in first }
    }

    static func firstLine(_ text: String) -> String {
        String(text.prefix { $0 != "\n" })
    }
}
