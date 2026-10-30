import Foundation

/// What a run kept about the moment each failed UI test failed, for Claude to look at before changing a test or a view:
/// per failed run, its configuration and device, the steps before the failure, the failure, and the screen at it.
public enum Look {
    /// Failed UI tests shown when none is named; the rest are named for a later look.
    static let mostTests = 3

    /// One test's look: its text, and whether any of its runs kept a screen, as a UI test's does.
    struct Looked {
        let text: String
        let hasScreen: Bool
    }

    /// What `look` says about one test in `bundle`, or, with none named, about its failed UI tests: those that kept a
    /// screen recording. Screens are kept under `folder`, in a folder per run, and runs kept there too long are removed.
    public static func report(bundle: ResultBundle, test: TestID?, keptIn folder: URL) async -> String {
        let name = URL(fileURLWithPath: bundle.path).lastPathComponent
        let run = bundle.runFolder(in: folder)
        FailureImages.prune(in: folder)
        if let test {
            return await look(at: test, in: bundle, named: name, keptIn: run)?.text ?? "xcrew: \(test.shown) didn't fail in \(name)"
        }
        let failed = await bundle.failedTests()
        guard !failed.isEmpty else { return "xcrew: nothing failed in \(name)" }
        // The first failed tests are looked up, a few at a time as FailureNotes does; the rest are only named.
        let lookups = Array(failed.prefix(FailureNotes.mostLookups))
        let looked = await withTaskGroup(of: (Int, Looked?).self) { group in
            var pending = lookups.enumerated().makeIterator()
            func lookUpNext() {
                guard let (index, test) = pending.next() else { return }
                group.addTask { (index, await look(at: test, in: bundle, named: name, keptIn: run)) }
            }
            for _ in 0..<FailureNotes.mostAtOnce { lookUpNext() }
            var found = [Looked?](repeating: nil, count: lookups.count)
            while let (index, result) = await group.next() {
                found[index] = result
                lookUpNext()
            }
            return found
        }
        let ui = zip(lookups, looked).compactMap { test, looked in looked.flatMap { $0.hasScreen ? (test, $0.text) : nil } }
        guard !ui.isEmpty else {
            return "xcrew: no failed test in \(name) kept a screen recording, as a UI test's failed run does; xcrew look <Suite/test> shows one test's steps"
        }
        let unshown = ui.dropFirst(mostTests).map(\.0) + failed.dropFirst(lookups.count)
        let more = unshown.isEmpty ? [] : ["and \(unshown.count) more failed \(unshown.count == 1 ? "test" : "tests"): " + unshown.map { "xcrew look \($0.shown)" }.joined(separator: ", ")]
        return (ui.prefix(mostTests).map(\.1) + more).joined(separator: "\n")
    }

    /// One test's failed runs, each with its steps, failure and screen; nil when no run of it failed.
    static func look(at test: TestID, in bundle: ResultBundle, named name: String, keptIn run: URL) async -> Looked? {
        let runs = FailedRun.runs(activities: await bundle.activities(of: test))
        guard !runs.isEmpty else { return nil }
        let screens = await bundle.attachments(of: test, onlyFailures: false, filter: FailureScreen.recordings) { export in
            let attachments = FailureImages.attachments(of: test, in: export)
            var screens: [FailureScreen?] = []
            for failed in runs { screens.append(await FailureScreen.keep(of: test, run: failed, attachments: attachments, from: export, in: run)) }
            return screens
        }
        var lines = ["xcrew look: \(test.shown), in \(name)"]
        for (failed, screen) in zip(runs, screens) {
            lines.append("  " + [failed.configuration, failed.device].filter { !$0.isEmpty }.joined(separator: " · "))
            lines += failed.steps.map { "    \(firstLine($0))" }
            lines += ["    ✗ \(firstLine(failed.failure))", "    " + screenLine(screen)]
        }
        return Looked(text: lines.joined(separator: "\n"), hasScreen: screens.contains { $0 != nil })
    }

    static func screenLine(_ screen: FailureScreen?) -> String {
        guard let screen else { return "screen: none; the run kept no screen recording of it that could be read" }
        return screen.secondsBefore < 1 ? "screen: \(screen.path)" : "screen: \(screen.path) (\(Int(screen.secondsBefore.rounded())) s before the failure)"
    }

    static func firstLine(_ text: String) -> String {
        String(text.prefix { $0 != "\n" })
    }
}
