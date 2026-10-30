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
}

/// The note on a build's warnings: those in lines the branch changed, named; never a claim about the rest.
@Suite struct WarningsInChangedLinesTests {
    static let base = "0123456789abcdef0123456789abcdef01234567"

    /// A project whose branch changed `Sources/Warn/Warn.swift`'s line 5, and a git that says so.
    func changed(_ project: Project, diff: String = "+++ Sources/Warn/Warn.swift\n@@ -4,0 +5 @@\n", remote: Bool = true) -> FakeRunner {
        let git = { (arguments: String) in "git -C \(project.root.path) \(arguments)" }
        var responses: [String: CommandResult] = [
            git("rev-parse --show-toplevel"): .init(status: 0, stdout: "\(project.root.path)\n"),
            git("diff --name-only --no-renames --no-relative -z \(Self.base)"): .init(status: 0, stdout: "Sources/Warn/Warn.swift\u{0}"),
            git("ls-files -z --others --exclude-standard --full-name"): .init(status: 0),
            git("-c core.quotePath=false diff -U0 --no-color --no-renames --no-relative --no-prefix \(Self.base)"): .init(status: 0, stdout: diff),
        ]
        if remote {
            responses[git("rev-parse --abbrev-ref origin/HEAD")] = .init(status: 0, stdout: "origin/main\n")
            responses[git("merge-base HEAD origin/main")] = .init(status: 0, stdout: "\(Self.base)\n")
        } else {
            responses[git("rev-parse --abbrev-ref origin/HEAD")] = .init(status: 128)
            responses[git("remote")] = .init(status: 0, stdout: "upstream\n")
        }
        return FakeRunner(responses: responses)
    }

    /// The compiler names files by their real path, `/private/var/...` for a temporary folder at `/var/...`.
    func build(in project: Project) -> String {
        let real = ProjectLayout.canonical(project.root)
        return Captured.text("mobileTestsPassedWithWarnings").replacingOccurrences(of: "/Users/dev/Warn", with: real)
    }

    @Test func aWarningInALineTheBranchChangedIsNamed() async {
        let project = Project.temporary(containing: ["Sources/Warn"])
        let report = await Report.make(kind: .test, output: ToolOutput(text: build(in: project), server: .mobileBuildMCP), home: Captured.home, runner: changed(project), project: project)
        let note = report.notes.first { $0.contains("lines this branch changed") }
        #expect(note?.contains("1 of 3 warnings") == true, "\(report.notes)")
        #expect(note?.contains("Warn.swift:5") == true)
        #expect(note?.contains("Warn.swift:4") == false)
    }

    @Test func noWarningInAChangedLineSaysNothing() async {
        let project = Project.temporary(containing: ["Sources/Warn"])
        let report = await Report.make(kind: .test, output: ToolOutput(text: build(in: project), server: .mobileBuildMCP), home: Captured.home, runner: changed(project, diff: "+++ Sources/Warn/Warn.swift\n@@ -40,0 +41 @@\n"), project: project)
        #expect(!report.notes.contains { $0.contains("lines this branch changed") || $0.contains("no new warnings") })
    }

    @Test func withoutABaseThereIsNoNote() async {
        let project = Project.temporary(containing: ["Sources/Warn"])
        let report = await Report.make(kind: .test, output: ToolOutput(text: build(in: project), server: .mobileBuildMCP), home: Captured.home, runner: changed(project, remote: false), project: project)
        #expect(!report.notes.contains { $0.contains("lines this branch changed") })
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
