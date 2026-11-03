import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// The lines a branch changed, from `git diff -U0`: a warning in one of them is the change's.
@Suite struct ChangedLinesTests {
    /// A hunk header gives the new side's start and count; a count of 0 adds no line, an omitted one means one line.
    @Test func hunksGiveTheNewSidesLines() {
        let diff = """
            diff --git Sources/A.swift Sources/A.swift
            --- Sources/A.swift
            +++ Sources/A.swift
            @@ -3,0 +4,2 @@ struct A {
            +    let a = 1
            +    let b = 2
            @@ -10 +12 @@
            -old
            +new
            @@ -20,3 +22,0 @@
            -gone
            --- /dev/null
            +++ Sources/B.swift
            @@ -0,0 +1,3 @@
            """
        let lines = ChangedLines.hunks(diff, top: "/repo")
        #expect(lines["/repo/Sources/A.swift"] == [4...5, 12...12])
        #expect(lines["/repo/Sources/B.swift"] == [1...3])
    }

    /// With no context, a removed line reading `-- a` and an added one reading `++ b` print like a file's header; inside a
    /// hunk they're its lines.
    @Test func aLineThatLooksLikeAHeaderStaysInItsHunk() {
        let diff = """
            --- Sources/A.swift
            +++ Sources/A.swift
            @@ -1 +1 @@
            --- old
            +++ new
            @@ -5,0 +6 @@
            +x
            """
        let lines = ChangedLines.hunks(diff, top: "/repo")
        #expect(lines == ["/repo/Sources/A.swift": [1...1, 6...6]])
    }

    /// Diff lines end at `\n` alone: a carriage return inside a changed line is part of it.
    @Test func aCarriageReturnDoesNotEndALine() {
        let diff = "+++ Sources/A.swift\n@@ -0,0 +1,2 @@\n+a\r+b\n+++ c\n@@ -8,0 +10 @@\n+d\n"
        #expect(ChangedLines.hunks(diff, top: "/repo") == ["/repo/Sources/A.swift": [1...2, 10...10]])
    }

    /// A file written with CRLF endings still ends each diff line at its `\n`.
    @Test func aCRLFLineEndsAtItsNewline() {
        let diff = "+++ Sources/A.swift\n@@ -0,0 +1,2 @@\n+x\r\n+y\n--- Sources/B.swift\n+++ Sources/B.swift\n@@ -3 +3 @@\n-q\n+r\n"
        #expect(ChangedLines.hunks(diff, top: "/repo") == ["/repo/Sources/A.swift": [1...2], "/repo/Sources/B.swift": [3...3]])
    }

    /// Against git itself, on a repository opened by its `/var` path: the compiler's `/private/var` spelling selects each
    /// file, a name with a space or a quote is read back as written, and an untracked file counts whole.
    @Test func gitGivesTheChangedLinesOfEveryKindOfName() async throws {
        let project = Project.temporary()
        let runner = SystemCommandRunner()
        func git(_ arguments: String...) async {
            _ = await runner.run(["git", "-C", project.root.path, "-c", "user.name=xcrew", "-c", "user.email=xcrew@example.com", "-c", "commit.gpgsign=false"] + arguments, stdin: nil, timeout: .seconds(30))
        }
        await git("init", "-q")
        project.write("a\nb\n", to: "My App/A b.swift")
        project.write("a\n", to: "Q\"t.swift")
        project.write("a\nb\nc\n", to: "Plain.swift")
        await git("add", ".")
        await git("commit", "-q", "--no-verify", "-m", "start")
        project.write("a\nB\n", to: "My App/A b.swift")
        project.write("A\n", to: "Q\"t.swift")
        project.write("a\nb\nc\nd\n", to: "Plain.swift")
        project.write("x\n", to: "New.swift")
        let real = ProjectLayout.canonical(project.root)
        #expect(real.hasPrefix("/private/"), "the temporary folder is expected under /private")
        let change = try await GitChanges.since(nil, in: project, using: runner).get()
        let lines = await ChangedLines.of(["My App/A b.swift", "Q\"t.swift", "Plain.swift", "New.swift"].map { "\(real)/\($0)" }, in: change, project: project, using: runner)
        #expect(lines == [
            "\(real)/My App/A b.swift": [2...2],
            "\(real)/Q\"t.swift": [1...1],
            "\(real)/Plain.swift": [4...4],
            "\(real)/New.swift": [1...Int.max],
        ])
    }
}

/// The note on a build's warnings: those in lines the branch changed, named; never a claim about the rest.
@Suite struct WarningsInChangedLinesTests {
    /// A project whose branch changed `Sources/Warn/Warn.swift`'s line 5, and a git that says so.
    func changed(_ project: Project, diff: String = "+++ Sources/Warn/Warn.swift\n@@ -4,0 +5 @@\n", remote: Bool = true) -> FakeRunner {
        FakeRunner(responses: FakeRunner.branch(at: project.root, changed: ["Sources/Warn/Warn.swift"], diffed: ["\(ProjectLayout.canonical(project.root))/Sources/Warn/Warn.swift"], diff: diff, remote: remote))
    }

    /// A project whose branch changed `Kit/Kit.swift`'s line 9, as the real build's concurrency fixture, and a git that
    /// says so.
    func kitChanged(_ project: Project, diff: String = "+++ Kit/Kit.swift\n@@ -8,0 +9 @@\n", remote: Bool = true) -> FakeRunner {
        FakeRunner(responses: FakeRunner.branch(at: project.root, changed: ["Kit/Kit.swift"], diffed: ["\(ProjectLayout.canonical(project.root))/Kit/Kit.swift"], diff: diff, remote: remote))
    }

    /// The real build's text or JSON with its warnings in `project`. The compiler names files by their real path,
    /// `/private/var/...` for a temporary folder at `/var/...`.
    func build(_ shape: (String) throws -> String, in project: Project) throws -> ToolOutput {
        ToolOutput(text: try shape("build_sim").replacingOccurrences(of: "/testbed/concurrency", with: ProjectLayout.canonical(project.root)), server: .mobileBuildMCP)
    }

    /// The real build lists 7 warnings; one is in the line the branch changed.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"), arguments: ["text", "JSON"])
    func aWarningInALineTheBranchChangedIsNamed(_ shape: String) async throws {
        let project = Project.temporary(containing: ["Kit"])
        let output = try build(shape == "text" ? Raw.text : Raw.json, in: project)
        let report = await Report.make(kind: .build, output: output, home: Captured.home, runner: kitChanged(project), project: project)
        let note = report.notes.first { $0.contains("lines this branch changed") }
        #expect(note?.contains("1 of 7 warnings") == true, "\(report.notes)")
        #expect(note?.contains("Kit.swift:9") == true)
        #expect(note?.contains("Kit.swift:1 ") == false)
    }

    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func noWarningInAChangedLineSaysNothing() async throws {
        let project = Project.temporary(containing: ["Kit"])
        let report = await Report.make(kind: .build, output: try build(Raw.text, in: project), home: Captured.home, runner: kitChanged(project, diff: "+++ Kit/Kit.swift\n@@ -40,0 +41 @@\n"), project: project)
        #expect(!report.notes.contains { $0.contains("lines this branch changed") || $0.contains("no new warnings") })
    }

    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func withoutABaseThereIsNoNote() async throws {
        let project = Project.temporary(containing: ["Kit"])
        let report = await Report.make(kind: .build, output: try build(Raw.text, in: project), home: Captured.home, runner: kitChanged(project, remote: false), project: project)
        #expect(!report.notes.contains { $0.contains("lines this branch changed") })
    }

    /// A warning the build lists twice at one place is one warning; one without a place still counts in the total.
    @Test func aWarningListedTwiceCountsOnce() async {
        let project = Project.temporary(containing: ["Sources/Warn"])
        let file = "\(ProjectLayout.canonical(project.root))/Sources/Warn/Warn.swift"
        let json = #"{"buildResult":"succeeded","errors":[{"classification":"warning","filePath":"\#(file)","lineNumber":5,"message":"unused x"},{"classification":"warning","filePath":"\#(file)","lineNumber":5,"message":"unused x"},{"classification":"warning","filePath":"\#(file)","lineNumber":9,"message":"unused y"},{"classification":"warning","message":"no place"},{"classification":"warning","message":"nowhere either"}]}"#
        let report = await Report.make(kind: .build, output: ToolOutput(text: json, server: .xcode), home: Captured.home, runner: changed(project), project: project)
        let note = report.notes.first { $0.contains("lines this branch changed") }
        #expect(note == "xcrew: 1 of 4 warnings are in lines this branch changed: Warn.swift:5 unused x.", "\(report.notes)")
    }

    /// On a case-insensitive volume a warning can spell the file's name in another case: the file is the same.
    @Test func aWarningSpellingTheFileInAnotherCaseIsNamed() async {
        let project = Project.temporary(containing: ["Sources/Warn"])
        project.write("let x = 1\n", to: "Sources/Warn/Warn.swift")
        let file = "\(ProjectLayout.canonical(project.root))/Sources/Warn/warn.swift"
        let json = #"{"buildResult":"succeeded","errors":[{"classification":"warning","filePath":"\#(file)","lineNumber":5,"message":"unused"}]}"#
        let report = await Report.make(kind: .build, output: ToolOutput(text: json, server: .xcode), home: Captured.home, runner: changed(project), project: project)
        #expect(report.notes.contains("xcrew: 1 of 1 warnings are in lines this branch changed: warn.swift:5 unused."), "\(report.notes)")
    }

    /// The Xcode MCP's build result carries its warnings too, with file and line.
    @Test func anXcodeMCPWarningInAChangedLineIsNamed() async {
        let project = Project.temporary(containing: ["Sources/Warn"])
        let file = "\(ProjectLayout.canonical(project.root))/Sources/Warn/Warn.swift"
        let json = #"{"buildResult":"succeeded","errors":[{"classification":"warning","filePath":"\#(file)","lineNumber":5,"message":"variable 'x' was never mutated"},{"classification":"warning","filePath":"\#(file)","lineNumber":9,"message":"unused"}]}"#
        let report = await Report.make(kind: .build, output: ToolOutput(text: json, server: .xcode), home: Captured.home, runner: changed(project), project: project)
        let note = report.notes.first { $0.contains("lines this branch changed") }
        #expect(note?.contains("1 of 2 warnings") == true, "\(report.notes)")
        #expect(note?.contains("never mutated") == true)
    }
}
