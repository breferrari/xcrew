import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// Of the lines a branch changed that can run, which a test run ran: read from the run's coverage archive.
@Suite struct ChangedLineCoverageTests {
    static let bundle = "/Users/dev/Library/Developer/MobileBuildMCP/workspaces/sample-0000/result-bundles/test_sim.xcresult"

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
    func run(_ project: Project, coverage: Bool = true, counts: [Int?] = [1, nil, 0, 2]) -> FakeRunner {
        let cart = "\(project.root.path)/Sources/Cart/Cart.swift"
        let lines = counts.enumerated().map { index, count in
            count.map { #"{"executionCount":\#($0),"isExecutable":true,"line":\#(index + 4)}"# } ?? #"{"isExecutable":false,"line":\#(index + 4)}"#
        }
        var responses = FakeRunner.branch(at: project.root, changed: ["Sources/Cart/Cart.swift", "Sources/Cart/CartView.swift", "README.md"], diffed: ["\(ProjectLayout.canonical(project.root))/Sources/Cart/Cart.swift"], diff: "+++ Sources/Cart/Cart.swift\n@@ -3,0 +4,4 @@\n")
        responses.merge([
            // Without coverage, xccov says "No coverage data in result bundle" and fails.
            "xcrun xccov view --archive --file-list --json \(Self.bundle)": coverage ? .init(status: 0, stdout: #"["\#(cart.replacingOccurrences(of: "/", with: "\\/"))"]"#) : .init(status: 1),
            "xcrun xccov view --archive --file \(cart) --json \(Self.bundle)": .init(status: 0, stdout: #"{"\#(cart)":[\#(lines.joined(separator: ","))]}"#),
        ]) { _, new in new }
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
        let report = await Report.make(kind: .test, output: ToolOutput(text: Captured.text("mobileTestsPassed"), server: .mobileBuildMCP), home: Captured.home, runner: runner, project: project)
        return report.notes.first { $0.contains("changed line") || $0.contains("changed file") }
    }

    @Test func aChangedLineTheRunDidNotRunIsNamed() async {
        let project = project()
        #expect(await note(project, run(project)) == "xcrew: 2 of 3 changed lines that can run ran in this test run. Not run: Cart.swift:6. 1 changed file isn't in this run's coverage: CartView.swift.")
    }

    @Test func everyChangedLineRan() async {
        let project = project()
        #expect(await note(project, run(project, counts: [1, nil, 5, 2])) == "xcrew: all 3 changed lines that can run ran in this test run. 1 changed file isn't in this run's coverage: CartView.swift.")
    }

    /// A file whose counts xccov can't give is unknown, not a file with no line that can run: no note claims a count.
    @Test func aFileXccovCannotReadLeavesNoNote() async {
        let project = project()
        var runner = run(project)
        runner.responses["xcrun xccov view --archive --file \(project.root.path)/Sources/Cart/Cart.swift --json \(Self.bundle)"] = .init(status: 1)
        #expect(await note(project, runner) == nil)
    }

    /// The archive can name one file in two spellings, as the build was started and as the file system spells it.
    @Test func aFileListedInTwoSpellingsCountsOnce() async {
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
    @Test func aManifestOrAFileOutsideTheProjectIsNeverNamed() async {
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

    @Test func withoutCoverageThereIsNoNote() async {
        let project = project()
        #expect(await note(project, run(project, coverage: false)) == nil)
    }

    @Test func aBuildHasNoNote() async {
        let project = project()
        let report = await Report.make(kind: .build, output: ToolOutput(text: Captured.text("mobileTestsPassed"), server: .mobileBuildMCP), home: Captured.home, runner: run(project), project: project)
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
    }
}
