import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// Of the lines a branch changed that can run, which a test run ran: read from the run's coverage archive.
@Suite struct ChangedLineCoverageTests {
    static var bundle: String { Raw.bundle("swift-testing") }

    /// `xccov view --archive --file <path> --json`, as probed: a line that can't run says so and has no count.
    @Test func eachLineThatCanRunSaysWhetherItRan() {
        let json = #"{"\/tmp\/A.swift":[{"isExecutable":false,"line":1},{"executionCount":0,"isExecutable":true,"line":2},{"executionCount":3,"isExecutable":true,"line":3}]}"#
        #expect(ChangedLineCoverage.lines(json) == [2: false, 3: true])
    }

    /// Past its budget the reading is dropped, so a slow archive can't cost the rest of the report.
    @Test func aReadingPastItsBudgetIsDropped() async {
        let slow = await ChangedLineCoverage.within(.milliseconds(50)) {
            try? await Task.sleep(for: .seconds(30))
            return ChangedLineCoverage(ran: 1)
        }
        #expect(slow == nil)
        #expect(await ChangedLineCoverage.within(.seconds(30)) { ChangedLineCoverage(ran: 1) } == ChangedLineCoverage(ran: 1))
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
        responses.merge([
            // Without coverage, xccov says "No coverage data in result bundle" and fails.
            "xcrun xccov view --archive --file-list --json \(bundle)": coverage ? .init(status: 0, stdout: #"[\#(([cart] + extra).map { #""\#($0.replacingOccurrences(of: "/", with: "\\/"))""# }.joined(separator: ","))]"#) : .init(status: 1),
            "xcrun xccov view --archive --file \(cart) --json \(bundle)": .init(status: 0, stdout: #"{"\#(cart)":[\#(lines.joined(separator: ","))]}"#),
        ]) { _, new in new }
        if let report { responses["xcrun xccov view --report --json \(bundle)"] = .init(status: 0, stdout: report) }
        return FakeRunner(responses: responses)
    }

    func project() -> Project {
        let project = Project.temporary(containing: ["Sources/Cart"])
        project.write("struct Cart {}\n", to: "Sources/Cart/Cart.swift")
        project.write("struct CartView {}\n", to: "Sources/Cart/CartView.swift")
        project.write("# Cart\n", to: "README.md")
        return project
    }

    func note(_ project: Project, _ runner: FakeRunner) async -> String? {
        let report = await Report.make(kind: .test, output: Raw.output("swift-testing"), home: Captured.home, runner: runner, project: project)
        return report.notes.first { $0.contains("changed line") || $0.contains("changed file") }
    }

    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aChangedLineTheRunDidNotRunIsNamed() async {
        let project = project()
        #expect(await note(project, run(project)) == "xcrew: 2 of 3 changed lines that can run ran in this test run. Not run: Cart.swift:6. 1 changed file isn't in this run's coverage: CartView.swift.")
    }

    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func everyChangedLineRan() async {
        let project = project()
        #expect(await note(project, run(project, counts: [1, nil, 5, 2])) == "xcrew: all 3 changed lines that can run ran in this test run. 1 changed file isn't in this run's coverage: CartView.swift.")
    }

    /// A file whose counts xccov can't give is unknown, not a file with no line that can run: no note claims a count.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aFileXccovCannotReadLeavesNoNote() async {
        let project = project()
        var runner = run(project)
        runner.responses["xcrun xccov view --archive --file \(project.root.path)/Sources/Cart/Cart.swift --json \(Self.bundle)"] = .init(status: 1)
        #expect(await note(project, runner) == nil)
    }

    /// The archive can name one file in two spellings, as the build was started and as the file system spells it.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aFileListedInTwoSpellingsCountsOnce() async {
        let project = project()
        var runner = run(project)
        let cart = "\(project.root.path)/Sources/Cart/Cart.swift", real = "\(ProjectLayout.canonical(project.root))/Sources/Cart/Cart.swift"
        let escaped = { (path: String) in path.replacingOccurrences(of: "/", with: "\\/") }
        runner.responses["xcrun xccov view --archive --file-list --json \(Self.bundle)"] = .init(status: 0, stdout: #"["\#(escaped(cart))","\#(escaped(real))"]"#)
        runner.responses["xcrun xccov view --archive --file \(real) --json \(Self.bundle)"] = runner.responses["xcrun xccov view --archive --file \(cart) --json \(Self.bundle)"]
        #expect(await note(project, runner) == "xcrew: 2 of 3 changed lines that can run ran in this test run. Not run: Cart.swift:6. 1 changed file isn't in this run's coverage: CartView.swift.")
    }

    /// A package or Tuist manifest is never in a run's coverage, and neither is a file outside the project, such as a
    /// server's code in the same repository: none is named.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aManifestOrAFileOutsideTheProjectIsNeverNamed() async {
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
        let found = await note(project, runner)
        #expect(found == "xcrew: 2 of 3 changed lines that can run ran in this test run. Not run: Cart.swift:6. 1 changed file isn't in this run's coverage: CartView.swift.")
    }

    /// A run of no tests ran none of the changed lines, as its coverage says, but says nothing of them: no note.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aRunOfNoTestsHasNoNote() async {
        let project = project()
        let report = await Report.make(kind: .test, output: Raw.jsonOutput("empty-filter"), home: Captured.home, runner: run(project, counts: [0, nil, 0, 0], bundle: Raw.bundle("empty-filter")), project: project)
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
    func aTestBundlesFilesAreLeftOut() async {
        let project = project()
        project.write("final class CartTests {}\n", to: "Sources/Cart/CartTests.swift")
        let cart = "\(project.root.path)/Sources/Cart/Cart.swift", tests = "\(project.root.path)/Sources/Cart/CartTests.swift"
        let report = Self.report([("Cart.framework", 2, [cart]), ("CartTests.xctest", 5, [tests])])
        #expect(await note(project, run(project, listed: [tests], changed: ["Sources/Cart/CartTests.swift"], report: report)) == "xcrew: 2 of 3 changed lines that can run ran in this test run. Not run: Cart.swift:6. 1 changed file isn't in this run's coverage: CartView.swift.")
    }

    /// A target none of whose lines ran wasn't reached by the run, as a filter leaves one out: it's said once, not its
    /// changed lines one by one.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aTargetTheRunDidNotReachIsSaidOnce() async {
        let project = project()
        let report = Self.report([("Cart.framework", 0, ["\(project.root.path)/Sources/Cart/Cart.swift"])])
        #expect(await note(project, run(project, counts: [0, nil, 0, 0], report: report)) == "xcrew: this test run ran nothing in Cart, where 1 changed file is. 1 changed file isn't in this run's coverage: CartView.swift.")
    }

    /// A file built into the app and into its test bundle too, as some projects add sources to a test target, is the
    /// app's code: it counts as the app's target was reached.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aFileInTheAppAndItsTestBundleCounts() async {
        let project = project()
        let cart = "\(project.root.path)/Sources/Cart/Cart.swift"
        let report = Self.report([("Cart.app", 2, [cart]), ("CartTests.xctest", 5, [cart])])
        #expect(await note(project, run(project, report: report)) == "xcrew: 2 of 3 changed lines that can run ran in this test run. Not run: Cart.swift:6. 1 changed file isn't in this run's coverage: CartView.swift.")
    }

    /// A target the run didn't reach after lines that ran: its own sentence, its file not named again as outside.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aTargetNotReachedAfterLinesThatRanIsItsOwnSentence() async {
        let project = project()
        let report = Self.report([("Cart.framework", 2, ["\(project.root.path)/Sources/Cart/Cart.swift"]), ("Widget.appex", 0, ["\(project.root.path)/Sources/Cart/CartView.swift"])])
        #expect(await note(project, run(project, report: report)) == "xcrew: 2 of 3 changed lines that can run ran in this test run. Not run: Cart.swift:6. This test run ran nothing in Widget, where 1 changed file is.")
    }

    /// A target with no line that can run, such as one of protocols and types alone, had nothing to run: it isn't one the
    /// run didn't reach.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aTargetWithNoLineThatCanRunIsNotUnreached() async {
        let project = project()
        let report = Self.report([("Cart.framework", 0, ["\(project.root.path)/Sources/Cart/Cart.swift"])], executable: 0)
        #expect(await note(project, run(project, counts: [nil, nil, nil, nil], report: report)) == "xcrew: 1 changed file isn't in this run's coverage: CartView.swift.")
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
    func withoutCoverageThereIsNoNote() async {
        let project = project()
        #expect(await note(project, run(project, coverage: false)) == nil)
    }

    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aBuildHasNoNote() async {
        let project = project()
        let report = await Report.make(kind: .build, output: Raw.output("swift-testing"), home: Captured.home, runner: run(project), project: project)
        #expect(!report.notes.contains { $0.contains("changed line") })
    }
}

/// xccov's answers on a bundle the canary makes fresh with the newest Xcode (`scripts/coverage-shape.sh`): their shape
/// isn't documented, so a change shows up here, not as a note that's silently empty.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["XCREW_COVERAGE_BUNDLE"] != nil, "no fresh bundle"))
struct LiveCoverageShapeTests {
    @Test func xccovStillAnswersInTheShapeXcrewReads() async throws {
        let bundle = ResultBundle(path: ProcessInfo.processInfo.environment["XCREW_COVERAGE_BUNDLE"] ?? "", runner: SystemCommandRunner())
        let files = await bundle.coveredFiles()
        let file = try #require(files.first, "no file in the coverage archive")
        let lines = ChangedLineCoverage.lines(await bundle.coverage(of: file))
        #expect(lines?.values.contains(true) == true, "no line of \(file) read as run: \(String(describing: lines))")
        let targets = CoverageTarget.targets(in: await bundle.coverageReport())
        #expect(targets.contains { $0.isTests && !$0.files.isEmpty }, "no test bundle with its files in xccov's report: \(targets)")
        #expect(targets.contains { $0.files.contains { ProjectLayout.canonicalPath($0.path) == ProjectLayout.canonicalPath(file) } }, "\(file) isn't in any target of xccov's report: \(targets)")
    }
}
