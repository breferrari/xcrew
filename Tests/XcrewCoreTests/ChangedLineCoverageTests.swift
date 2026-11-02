import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// Of the lines a branch changed that can run, which a test run ran: read from the run's coverage archive.
@Suite struct ChangedLineCoverageTests {
    static let bundle = Raw.passingBundle

    /// `xccov view --archive --file <path> --json`, as probed: a line that can't run says so and has no count.
    @Test func eachLineThatCanRunSaysWhetherItRan() {
        let json = #"{"\/tmp\/A.swift":[{"isExecutable":false,"line":1},{"executionCount":0,"isExecutable":true,"line":2},{"executionCount":3,"isExecutable":true,"line":3}]}"#
        #expect(ChangedLineCoverage.lines(json) == [2: false, 3: true])
    }

    /// Across a branch's runs, a changed line ran when any run ran it; a file is outside the coverage, and a target
    /// unreached, only when it is in every run.
    @Test func runsMergeIntoWhatAnyOfThemRan() {
        let first = ChangedLineCoverage(lines: ["/p/Cart.swift": [4: true, 6: false, 7: true]], outside: ["/p/A.swift", "/p/B.swift"], unreached: [.init(target: "Feature", files: 1)])
        let second = ChangedLineCoverage(lines: ["/p/Cart.swift": [4: false, 6: true, 7: false], "/p/Pay.swift": [2: false]], outside: ["/p/A.swift"], unreached: [])
        let merged = ChangedLineCoverage.merged([first, second])
        #expect(merged.ran == 3)
        #expect(merged.notRun == [.init(path: "/p/Pay.swift", lines: [2])])
        #expect(merged.outside == ["/p/A.swift"])
        #expect(merged.unreached == [])
    }

    /// A run speaks only for the changed files unchanged since it started: a file modified later holds content the run
    /// never compiled, so its lines there would name the wrong ones.
    @Test func aRunSpeaksOnlyForFilesUnchangedSinceItStarted() {
        let run = ChangedLineCoverage(lines: ["/p/Cart.swift": [4: true], "/p/Pay.swift": [2: true]])
        let modified = ["/p/Cart.swift": Date(timeIntervalSince1970: 100), "/p/Pay.swift": Date(timeIntervalSince1970: 300)]
        let fresh = run.fresh(since: Date(timeIntervalSince1970: 200)) { modified[$0] }
        #expect(fresh.lines == ["/p/Cart.swift": [4: true]])
        #expect(fresh.stale == ["/p/Pay.swift"])
    }

    /// A changed file every run that covered it is older than says so, as neither run nor not run.
    @Test func aFileChangedSinceEveryRunIsSaidSo() {
        let first = ChangedLineCoverage(lines: ["/p/Cart.swift": [4: true]], stale: ["/p/Pay.swift"])
        let second = ChangedLineCoverage(lines: ["/p/Cart.swift": [4: false]], stale: ["/p/Pay.swift", "/p/Cart.swift"])
        let merged = ChangedLineCoverage.merged([first, second])
        #expect(merged.stale == ["/p/Pay.swift"])
        #expect(merged.sentence == "the 1 changed line that can run ran in these test runs. 1 changed file changed after every run that covered it: Pay.swift.")
    }

    /// Only runs that started once the earliest changed file had its last change can speak for any, newest first.
    @Test func onlyRunsStartedSinceTheEarliestChangeCanSpeak() {
        let at = { Date(timeIntervalSince1970: $0) }
        let runs = [BranchCoverage.Run(path: "/r/a", started: at(90), finished: at(95)), BranchCoverage.Run(path: "/r/b", started: at(110), finished: at(120)), BranchCoverage.Run(path: "/r/c", started: at(130), finished: at(140))]
        #expect(BranchCoverage.candidates(runs, lastChanges: [at(200), at(100)])?.map(\.path) == ["/r/c", "/r/b"])
    }

    /// A run starts when MobileBuildMCP names its bundle, before it builds (`utils/test-common.js`); the folder itself is
    /// made later, in the test phase. A name it can't read gives no start, so the run can't speak.
    @Test func aRunStartsWhenItsBundleIsNamed() {
        #expect(BranchCoverage.started("test_sim_2026-10-31T04-52-13-599Z_pid35682_04a7243e.xcresult") == Date(timeIntervalSince1970: 1_793_422_333.599))
        #expect(BranchCoverage.started("Run.xcresult") == nil)
    }

    /// A run whose tests were all skipped ran none, as one of no tests didn't.
    @Test func aRunOfOnlySkippedTestsRanNone() {
        #expect(!BranchCoverage.ranTests(summary: #"{"totalTestCount":3,"passedTests":0,"failedTests":0,"skippedTests":3}"#))
        #expect(BranchCoverage.ranTests(summary: #"{"totalTestCount":3,"passedTests":1,"failedTests":0,"skippedTests":2}"#))
        #expect(BranchCoverage.ranTests(summary: ""))
    }

    /// Two runs spelling one file two ways, as the build was started and as the file system spells it, merge as one file.
    @Test func runsSpellingAFileTwoWaysMergeIntoOne() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "xcrew-spell-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "Cart.swift")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let first = ChangedLineCoverage(lines: [file.path: [4: true]])
        let second = ChangedLineCoverage(lines: [ProjectLayout.canonicalPath(file.path): [4: false, 5: false]])
        #expect(ChangedLineCoverage.merged([first, second]).ran == 1)
        #expect(ChangedLineCoverage.merged([first, second]).notRun.map(\.lines) == [[5]])
    }

    /// A stale file two runs spell two ways is named once.
    @Test func aStaleFileSpelledTwoWaysIsNamedOnce() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "xcrew-stale-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "Pay.swift")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let merged = ChangedLineCoverage.merged([ChangedLineCoverage(stale: [file.path]), ChangedLineCoverage(stale: [ProjectLayout.canonicalPath(file.path)])])
        #expect(merged.stale.count == 1)
    }

    /// With no changed file's date to go by, as on a branch that only deletes files, no run is chosen or ruled out.
    @Test func noDateChoosesNoRun() {
        let run = BranchCoverage.Run(path: "/r/a", started: Date(timeIntervalSince1970: 100), finished: Date(timeIntervalSince1970: 200))
        #expect(BranchCoverage.candidates([run], lastChanges: []) == nil)
    }

    /// When the runs read say nothing but some were left out, the cut-off is said; with nothing left out, nothing is.
    @Test func runsThatSaidNothingWithSomeLeftOutSayTheCutOff() {
        let line = "- No test run read in the time allowed speaks for the changed lines: 2 runs are left out."
        #expect(BranchCoverage.together([], leftOut: 2)?.line(lastCommit: nil) == line)
        #expect(BranchCoverage.together([(ChangedLineCoverage(), Date(timeIntervalSince1970: 100))], leftOut: 2)?.line(lastCommit: nil) == line)
        #expect(BranchCoverage.together([], leftOut: 0) == nil)
    }

    /// Runs that each hold none of the changed lines yet agree a file is outside their coverage are all named.
    @Test func runsAgreeingOnlyOnWhatTheyDontHoldAreAllNamed() throws {
        let outside = ChangedLineCoverage(outside: ["/p/A.swift"])
        let together = try #require(BranchCoverage.together([(outside, Date(timeIntervalSince1970: 200)), (outside, Date(timeIntervalSince1970: 100))], leftOut: 0))
        #expect(together.finished == [Date(timeIntervalSince1970: 200), Date(timeIntervalSince1970: 100)])
        #expect(together.sentence == "1 changed file isn't in these runs' coverage: A.swift.")
    }

    /// A file the run covered whose changed lines can't run is held with none, so the run still speaks for it: an older
    /// run's lines there don't make it a file no run covered.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aCoveredFileWithNoChangedLineThatCanRunIsHeld() async throws {
        let project = project()
        let runner = run(project, counts: [nil, nil, nil, nil])
        guard case let .success(change) = await GitChanges.since(nil, in: project, using: runner) else { Issue.record("no change"); return }
        let found = try #require(await ChangedLineCoverage.of(ResultBundle(path: Self.bundle, runner: runner), change: { change }, project: project, using: runner))
        #expect(found.lines.count == 1 && found.lines.values.allSatisfy(\.isEmpty), "\(found.lines)")
    }

    /// The runs named are those that spoke for a line; a run whose every file changed since says nothing.
    @Test func onlyRunsThatSpokeAreCounted() {
        let spoke = ChangedLineCoverage(lines: ["/p/Cart.swift": [4: true]])
        let silent = ChangedLineCoverage(stale: ["/p/Pay.swift"])
        #expect(ChangedLineCoverage.merged([spoke, silent]).runs == 1)
        #expect(ChangedLineCoverage.merged([spoke, silent]).sentence == "the 1 changed line that can run ran in this test run. 1 changed file changed after every run that covered it: Pay.swift.")
    }

    /// Several runs are spoken of as these.
    @Test func severalRunsAreSpokenOfAsThese() {
        let runs = ChangedLineCoverage(lines: ["/p/Cart.swift": [4: true]], outside: ["/p/A.swift"], unreached: [.init(target: "Feature", files: 1)], runs: 2)
        #expect(runs.sentence == "the 1 changed line that can run ran in these test runs. These test runs ran nothing in Feature, where 1 changed file is. 1 changed file isn't in these runs' coverage: A.swift.")
    }

    @Test func linesNotRunAreNamedAsRanges() {
        #expect(ChangedLineCoverage.ranges([10, 6, 7, 8]) == ["6-8", "10"])
    }

    /// A project whose branch changed lines 4 to 7 of `Cart.swift` and all of `CartView.swift` and `README.md`, and a
    /// test run whose coverage holds `Cart.swift` alone, named as the build was started: by the project's `/var` path.
    func run(_ project: Project, coverage: Bool = true, counts: [Int?] = [1, nil, 0, 2], listed extra: [String] = [], changed: [String] = [], report: String? = nil, bundle: String = Self.bundle) -> FakeRunner {
        let cart = "\(project.root.path)/Sources/Cart/Cart.swift"
        let lines = counts.enumerated().map { index, count in
            count.map { #"{"executionCount":\#($0),"isExecutable":true,"line":\#(index + 4)}"# } ?? #"{"isExecutable":false,"line":\#(index + 4)}"#
        }
        var responses = FakeRunner.branch(at: project.root, changed: ["Sources/Cart/Cart.swift", "Sources/Cart/CartView.swift", "README.md"] + changed, diffed: ["\(ProjectLayout.canonical(project.root))/Sources/Cart/Cart.swift"], diff: "+++ Sources/Cart/Cart.swift\n@@ -3,0 +4,4 @@\n")
        responses["xcrun xccov view --archive --file \(cart) --json \(bundle)"] = .init(status: 0, stdout: #"{"\#(cart)":[\#(lines.joined(separator: ","))]}"#)
        responses[Self.availability(bundle)] = .init(status: 0, stdout: Self.available(coverage: coverage))
        // Without coverage, xccov says "No coverage data in result bundle" and fails.
        responses["xcrun xccov view --report --json \(bundle)"] = coverage ? .init(status: 0, stdout: report ?? Self.report([("Cart.framework", 2, [cart] + extra)])) : .init(status: 1)
        return FakeRunner(responses: responses)
    }

    static func availability(_ bundle: String) -> String {
        "xcrun xcresulttool get content-availability --path \(bundle) --compact"
    }

    /// `xcresulttool get content-availability --compact`'s answer, as Xcode 27.2 gave it on November 2, 2026.
    static func available(coverage: Bool) -> String {
        #"{"hasCoverage":\#(coverage),"hasDiagnostics":true,"hasTestResults":true,"logs":["action"]}"#
    }

    func project() -> Project {
        let project = Project.temporary(containing: ["Sources/Cart"])
        project.write("struct Cart {}\n", to: "Sources/Cart/Cart.swift")
        project.write("struct CartView {}\n", to: "Sources/Cart/CartView.swift")
        project.write("# Cart\n", to: "README.md")
        return project
    }

    func note(_ project: Project, _ runner: any CommandRunning) async throws -> String? {
        let report = await Report.make(kind: .test, output: try Raw.output("swift-testing"), home: Captured.home, runner: runner, project: project)
        return report.notes.first { $0.contains("changed line") || $0.contains("changed file") }
    }

    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aChangedLineTheRunDidNotRunIsNamed() async throws {
        let project = project()
        #expect(try await note(project, run(project)) == "xcrew: 2 of 3 changed lines that can run ran in this test run. Not run: Cart.swift:6. 1 changed file isn't in this run's coverage: CartView.swift.")
    }

    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func everyChangedLineRan() async throws {
        let project = project()
        #expect(try await note(project, run(project, counts: [1, nil, 5, 2])) == "xcrew: all 3 changed lines that can run ran in this test run. 1 changed file isn't in this run's coverage: CartView.swift.")
    }

    /// A file whose counts xccov can't give is unknown, not a file with no line that can run: no note claims a count.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aFileXccovCannotReadLeavesNoNote() async throws {
        let project = project()
        var runner = run(project)
        runner.responses["xcrun xccov view --archive --file \(project.root.path)/Sources/Cart/Cart.swift --json \(Self.bundle)"] = .init(status: 1)
        #expect(try await note(project, runner) == nil)
    }

    /// The report can name one file in two spellings, as the build was started and as the file system spells it.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aFileListedInTwoSpellingsCountsOnce() async throws {
        let project = project()
        var runner = run(project)
        let cart = "\(project.root.path)/Sources/Cart/Cart.swift", real = "\(ProjectLayout.canonical(project.root))/Sources/Cart/Cart.swift"
        runner.responses["xcrun xccov view --report --json \(Self.bundle)"] = .init(status: 0, stdout: Self.report([("Cart.framework", 2, [cart]), ("Cart.app", 2, [real])]))
        runner.responses["xcrun xccov view --archive --file \(real) --json \(Self.bundle)"] = runner.responses["xcrun xccov view --archive --file \(cart) --json \(Self.bundle)"]
        #expect(try await note(project, runner) == "xcrew: 2 of 3 changed lines that can run ran in this test run. Not run: Cart.swift:6. 1 changed file isn't in this run's coverage: CartView.swift.")
    }

    /// A package or Tuist manifest is never in a run's coverage, and neither is a file outside the project, such as a
    /// server's code in the same repository: none is named.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aManifestOrAFileOutsideTheProjectIsNeverNamed() async throws {
        let project = project()
        project.write("// swift-tools-version:6.0\n", to: "Package.swift")
        project.write("let tuist = 1\n", to: "Tuist.swift")
        let server = project.root.deletingLastPathComponent().appending(path: "Server-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: server, withIntermediateDirectories: true)
        try? "struct Api {}\n".write(to: server.appending(path: "Api.swift"), atomically: true, encoding: .utf8)
        // The repository's top is the folder above the project, which holds the server beside it.
        var runner = run(project)
        let app = project.root.lastPathComponent, git = { (arguments: String) in "git -C \(project.root.path) \(arguments)" }
        runner.responses[git("rev-parse --show-toplevel")] = .init(status: 0, stdout: "\(project.root.deletingLastPathComponent().path)\n")
        let files = ["Sources/Cart/Cart.swift", "Sources/Cart/CartView.swift", "README.md", "Package.swift", "Tuist.swift"].map { "\(app)/\($0)" } + ["\(server.lastPathComponent)/Api.swift"]
        runner.responses[git("diff --name-only --no-renames --no-relative -z \(FakeRunner.base)")] = .init(status: 0, stdout: files.map { "\($0)\u{0}" }.joined())
        let diff = git("-c core.quotePath=false diff -U0 --no-color --no-renames --no-relative --no-prefix \(FakeRunner.base) -- \(ProjectLayout.canonical(project.root))/Sources/Cart/Cart.swift")
        runner.responses[diff] = .init(status: 0, stdout: "+++ \(app)/Sources/Cart/Cart.swift\n@@ -3,0 +4,4 @@\n")
        let found = try await note(project, runner)
        #expect(found == "xcrew: 2 of 3 changed lines that can run ran in this test run. Not run: Cart.swift:6. 1 changed file isn't in this run's coverage: CartView.swift.")
    }

    /// A run of no tests ran none of the changed lines, as its coverage says, but says nothing of them: no note.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aRunOfNoTestsHasNoNote() async throws {
        let project = project()
        let report = await Report.make(kind: .test, output: try Raw.jsonOutput("empty-filter"), home: Captured.home, runner: run(project, counts: [0, nil, 0, 0], bundle: try Raw.bundle("empty-filter")), project: project)
        #expect(report.tests == 0)
        #expect(!report.notes.contains { $0.contains("changed line") || $0.contains("changed file") })
    }

    /// xccov's report, each target with how many of its lines ran and its files, by path.
    static func report(_ targets: [(name: String, covered: Int, files: [String])], executable: Int = 10) -> String {
        let listed = targets.map { target in
            #"{"name":"\#(target.name)","coveredLines":\#(target.covered),"executableLines":\#(executable),"files":[\#(target.files.map { #"{"name":"\#(ToolOutput.basename($0))","path":"\#($0)"}"# }.joined(separator: ","))]}"#
        }
        return #"{"coveredLines":5,"executableLines":20,"targets":[\#(listed.joined(separator: ","))]}"#
    }

    /// A test bundle's files are the tests, not the code they test: a changed test file is neither counted nor named.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aTestBundlesFilesAreLeftOut() async throws {
        let project = project()
        project.write("final class CartTests {}\n", to: "Sources/Cart/CartTests.swift")
        let cart = "\(project.root.path)/Sources/Cart/Cart.swift", tests = "\(project.root.path)/Sources/Cart/CartTests.swift"
        let report = Self.report([("Cart.framework", 2, [cart]), ("CartTests.xctest", 5, [tests])])
        #expect(try await note(project, run(project, listed: [tests], changed: ["Sources/Cart/CartTests.swift"], report: report)) == "xcrew: 2 of 3 changed lines that can run ran in this test run. Not run: Cart.swift:6. 1 changed file isn't in this run's coverage: CartView.swift.")
    }

    /// A target none of whose lines ran wasn't reached by the run, as a filter leaves one out: it's said once, not its
    /// changed lines one by one.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aTargetTheRunDidNotReachIsSaidOnce() async throws {
        let project = project()
        let report = Self.report([("Cart.framework", 0, ["\(project.root.path)/Sources/Cart/Cart.swift"])])
        #expect(try await note(project, run(project, counts: [0, nil, 0, 0], report: report)) == "xcrew: this test run ran nothing in Cart, where 1 changed file is. 1 changed file isn't in this run's coverage: CartView.swift.")
    }

    /// A file built into the app and into its test bundle too, as some projects add sources to a test target, is the
    /// app's code: it counts as the app's target was reached.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aFileInTheAppAndItsTestBundleCounts() async throws {
        let project = project()
        let cart = "\(project.root.path)/Sources/Cart/Cart.swift"
        let report = Self.report([("Cart.app", 2, [cart]), ("CartTests.xctest", 5, [cart])])
        #expect(try await note(project, run(project, report: report)) == "xcrew: 2 of 3 changed lines that can run ran in this test run. Not run: Cart.swift:6. 1 changed file isn't in this run's coverage: CartView.swift.")
    }

    /// A target the run didn't reach after lines that ran: its own sentence, its file not named again as outside.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aTargetNotReachedAfterLinesThatRanIsItsOwnSentence() async throws {
        let project = project()
        let report = Self.report([("Cart.framework", 2, ["\(project.root.path)/Sources/Cart/Cart.swift"]), ("Widget.appex", 0, ["\(project.root.path)/Sources/Cart/CartView.swift"])])
        #expect(try await note(project, run(project, report: report)) == "xcrew: 2 of 3 changed lines that can run ran in this test run. Not run: Cart.swift:6. This test run ran nothing in Widget, where 1 changed file is.")
    }

    /// A target with no line that can run, such as one of protocols and types alone, had nothing to run: it isn't one the
    /// run didn't reach.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aTargetWithNoLineThatCanRunIsNotUnreached() async throws {
        let project = project()
        let report = Self.report([("Cart.framework", 0, ["\(project.root.path)/Sources/Cart/Cart.swift"])], executable: 0)
        #expect(try await note(project, run(project, counts: [nil, nil, nil, nil], report: report)) == "xcrew: 1 changed file isn't in this run's coverage: CartView.swift.")
    }

    /// A package's report names its test target without the bundle's extension, `ShapeTests`; its product is the
    /// bundle, as Xcode 27.2's xccov gave it on October 30, 2026.
    @Test func aPackagesTestTargetIsToldByItsProduct() {
        let targets = CoverageTarget.targets(in: #"{"targets":[{"name":"ShapeTests","buildProductPath":"\/d\/Build\/Products\/Debug\/ShapeTests.xctest\/Contents\/MacOS\/ShapeTests","coveredLines":3,"executableLines":3,"files":[{"path":"\/p\/Tests\/ShapeTests\/ShapeTests.swift"}]}]}"#)
        #expect(targets.map(\.isTests) == [true])
    }

    /// One target in a shape xcrew doesn't read leaves the others read.
    @Test func anOddTargetLeavesTheOthersRead() {
        let targets = CoverageTarget.targets(in: #"{"targets":[{"name":"A.framework"},{"name":"B.xctest","coveredLines":1,"executableLines":2,"files":[{"path":"\/b"}]}]}"#)
        #expect(targets.map(\.name) == ["B.xctest"])
    }

    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func withoutCoverageThereIsNoNote() async throws {
        let project = project()
        #expect(try await note(project, run(project, coverage: false)) == nil)
    }

    /// A bundle that says it holds no coverage asks nothing of `xccov`, whose start alone takes over half a second.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aBundleWithoutCoverageAsksNothingOfXccov() async throws {
        let project = project()
        var runner = run(project)
        runner.responses[Self.availability(Self.bundle)] = .init(status: 0, stdout: Self.available(coverage: false))
        let recording = RecordingRunner(runner)
        #expect(try await note(project, recording) == nil)
        #expect(!recording.asked.contains { $0.hasPrefix("xcrun xccov") }, "\(recording.asked)")
    }

    /// With coverage, `xccov` is asked for its report and each changed file's lines, never the archive's file list: the
    /// report names the same files.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func theReportAloneNamesTheFilesCovered() async throws {
        let project = project()
        let recording = RecordingRunner(run(project))
        #expect(try await note(project, recording) == "xcrew: 2 of 3 changed lines that can run ran in this test run. Not run: Cart.swift:6. 1 changed file isn't in this run's coverage: CartView.swift.")
        #expect(!recording.asked.contains { $0.contains("--file-list") }, "\(recording.asked)")
    }

    /// A bundle that can't say whether it holds coverage has its report read all the same.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aBundleThatCantSayHasItsReportRead() async throws {
        let project = project()
        var runner = run(project)
        runner.responses[Self.availability(Self.bundle)] = .init(status: 64)
        #expect(try await note(project, runner) == "xcrew: 2 of 3 changed lines that can run ran in this test run. Not run: Cart.swift:6. 1 changed file isn't in this run's coverage: CartView.swift.")
    }

    /// `hasCoverage` is read from `content-availability`'s answer; an answer without it, or none, says nothing.
    @Test func contentAvailabilitySaysWhetherThereIsCoverage() async {
        let answers: [(CommandResult, Bool?)] = [
            (.init(status: 0, stdout: Self.available(coverage: true)), true),
            (.init(status: 0, stdout: Self.available(coverage: false)), false),
            (.init(status: 0, stdout: #"{"logs":["action"]}"#), nil),
            (.init(status: 64), nil),
        ]
        for (answer, expected) in answers {
            let runner = FakeRunner(responses: [Self.availability("/b.xcresult"): answer])
            #expect(await ResultBundle(path: "/b.xcresult", runner: runner).holdsCoverage() == expected, "\(answer)")
        }
    }

    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aBuildHasNoNote() async throws {
        let project = project()
        let report = await Report.make(kind: .build, output: try Raw.output("swift-testing"), home: Captured.home, runner: run(project), project: project)
        #expect(!report.notes.contains { $0.contains("changed line") })
    }

    /// `AppUITests`, a UI test target, builds its folder but for `Moved.swift`, which an exception set moves and which it
    /// also lists, and compiles `Shared.swift`, which `App` only copies as a resource. No target lists `Loose.swift`.
    static let testTargetFiles = """
        // !$*UTF8*$!
        { archiveVersion = 1; objects = {
          G = { isa = PBXGroup; sourceTree = "<group>"; children = (F, SH, MV); };
          F = { isa = PBXFileSystemSynchronizedRootGroup; path = AppUITests; sourceTree = "<group>"; exceptions = (E); };
          E = { isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = (Moved.swift); target = TT; };
          SH = { isa = PBXFileReference; path = Shared.swift; sourceTree = "<group>"; };
          MV = { isa = PBXFileReference; path = AppUITests/Moved.swift; sourceTree = "<group>"; };
          TA = { isa = PBXNativeTarget; name = App; productType = "com.apple.product-type.application"; buildPhases = (RES); };
          RES = { isa = PBXResourcesBuildPhase; files = (BR); };
          BR = { isa = PBXBuildFile; fileRef = SH; };
          TT = { isa = PBXNativeTarget; name = AppUITests; productType = "com.apple.product-type.bundle.ui-testing"; fileSystemSynchronizedGroups = (F); buildPhases = (SRC); };
          SRC = { isa = PBXSourcesBuildPhase; files = (BS, BM); };
          BS = { isa = PBXBuildFile; fileRef = SH; };
          BM = { isa = PBXBuildFile; fileRef = MV; };
        }; rootObject = G; }
        """

    static func testTargetProject() -> (project: Project, root: String) {
        let project = Project.temporary(containing: ["App.xcodeproj", "AppUITests"])
        project.write(Self.testTargetFiles, to: "App.xcodeproj/project.pbxproj")
        return (project, ProjectLayout.canonical(project.root))
    }

    /// A Swift file only a test target compiles is a test file, though the app copies it. A file an exception set moves
    /// may be built anywhere, and one no target lists by nothing the reading knows: both stay.
    @Test func onlyAFileATestTargetAloneBuildsIsLeftOut() {
        let (project, root) = Self.testTargetProject()
        let files = ["AppUITests/Plain.swift", "AppUITests/Moved.swift", "Shared.swift", "Loose.swift"].map { "\(root)/\($0)" }
        #expect(ChangedLineCoverage.withoutTestFiles(files, of: project) == ["\(root)/AppUITests/Moved.swift", "\(root)/Loose.swift"])
    }

    /// Once the coverage's budget has passed, the project's targets aren't read: every file keeps its place.
    @Test func pastTheBudgetTheTargetsArentRead() async {
        let (project, root) = Self.testTargetProject()
        let files = ["\(root)/AppUITests/Plain.swift"]
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return ChangedLineCoverage.withoutTestFiles(files, of: project)
        }
        task.cancel()
        #expect(await task.value == files)
    }
}

/// xcresulttool's and xccov's answers on a bundle the canary makes fresh with the newest Xcode
/// (`scripts/coverage-shape.sh`): xccov's shape isn't documented, so a change shows up here, not as a note that's
/// silently empty.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["XCREW_COVERAGE_BUNDLE"] != nil, "no fresh bundle"))
struct LiveCoverageShapeTests {
    @Test func xccovStillAnswersInTheShapeXcrewReads() async throws {
        let bundle = ResultBundle(path: ProcessInfo.processInfo.environment["XCREW_COVERAGE_BUNDLE"] ?? "", runner: SystemCommandRunner())
        #expect(await bundle.holdsCoverage() == true, "xcresulttool's content-availability doesn't say the bundle holds coverage")
        let targets = CoverageTarget.targets(in: await bundle.coverageReport())
        #expect(targets.contains { $0.isTests && !$0.files.isEmpty }, "no test bundle with its files in xccov's report: \(targets)")
        let file = try #require(targets.flatMap(\.files).first?.path, "no file in xccov's report: \(targets)")
        let lines = ChangedLineCoverage.lines(await bundle.coverage(of: file))
        #expect(lines?.values.contains(true) == true, "no line of \(file) read as run: \(String(describing: lines))")
    }
}
