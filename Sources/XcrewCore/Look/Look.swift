import Foundation

/// What a run kept about the moment each failed UI test failed, for Claude to look at before changing a test or a view:
/// per failed run, its configuration and device, the steps before the failure, the failure, and the screen at it.
public enum Look {
    /// Failed UI tests shown when none is named; the rest are named for a later look.
    static let mostTests = 3
    /// Failed tests looked up when none is named, for whether they're UI tests.
    static let mostLookups = 10

    /// What `look` says about one test in `bundle`, or, with none named, about its failed UI tests: those that kept a
    /// screen recording. Screens are kept under `folder`, in a folder per run, and runs kept there too long are removed.
    public static func report(bundle: ResultBundle, test: TestID?, keptIn folder: URL) async -> String {
        let name = URL(fileURLWithPath: bundle.path).lastPathComponent
        let run = folder.appending(path: URL(fileURLWithPath: bundle.path).deletingPathExtension().lastPathComponent)
        FailureImages.prune(in: folder)
        if let test {
            return await look(at: test, in: bundle, named: name, keptIn: run)?.text ?? "xcrew: \(test.shown) didn't fail in \(name)"
        }
        let failed = await bundle.failedTests()
        guard !failed.isEmpty else { return "xcrew: nothing failed in \(name)" }
        var shown: [String] = []
        var unlooked: [TestID] = []
        for (index, test) in failed.enumerated() {
            guard shown.count < mostTests, index < mostLookups else {
                unlooked.append(test)
                continue
            }
            if let looked = await look(at: test, in: bundle, named: name, keptIn: run), looked.hasScreen { shown.append(looked.text) }
        }
        guard !shown.isEmpty else {
            return "xcrew: no failed test in \(name) kept a screen recording, as a UI test's failed run does; xcrew look <Suite/test> shows one test's steps"
        }
        let more = unlooked.isEmpty ? [] : ["and \(unlooked.count) more failed \(unlooked.count == 1 ? "test" : "tests"): " + unlooked.map { "xcrew look \($0.shown)" }.joined(separator: ", ")]
        return (shown + more).joined(separator: "\n")
    }

    /// One test's failed runs, each with its steps, failure and screen; nil when no run of it failed.
    static func look(at test: TestID, in bundle: ResultBundle, named name: String, keptIn run: URL) async -> (text: String, hasScreen: Bool)? {
        let runs = FailedRun.runs(activities: await bundle.activities(of: test))
        guard !runs.isEmpty else { return nil }
        let export = await bundle.exportedAttachments(of: test)
        defer { export.map { try? FileManager.default.removeItem(at: $0) } }
        var lines = ["xcrew look: \(test.shown), in \(name)"]
        var hasScreen = false
        for failed in runs {
            let screen = if let export { await FailureScreen.keep(of: test, run: failed, from: export, in: run) } else { FailureScreen?.none }
            hasScreen = hasScreen || screen != nil
            lines.append("  " + [failed.configuration, failed.device].filter { !$0.isEmpty }.joined(separator: " · "))
            lines += failed.steps.map { "    \(firstLine($0))" }
            lines.append("    ✗ \(firstLine(failed.failure))")
            lines.append("    " + screenLine(screen))
        }
        return (lines.joined(separator: "\n"), hasScreen)
    }

    static func screenLine(_ screen: FailureScreen?) -> String {
        guard let screen else { return "screen: none; the run kept no screen recording, which the test plan's settings turn off" }
        return screen.secondsBefore < 1 ? "screen: \(screen.path)" : "screen: \(screen.path) (\(Int(screen.secondsBefore.rounded())) s before the failure)"
    }

    static func firstLine(_ text: String) -> String {
        text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? text
    }
}
