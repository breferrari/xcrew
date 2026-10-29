import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// Real results from MobileBuildMCP 2.7.1 and the Xcode MCP (Xcode 27.1), and `xcresulttool`'s
/// output, captured against a sample Swift package with machine paths replaced.
enum Captured {
    static func text(_ name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures/Reports")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    static func output(_ name: String, isError: Bool = false) -> ToolOutput {
        ToolOutput(text: text(name), isError: isError)
    }

    static let home = "/Users/dev"
    static let workspace = "/Users/dev/Library/Developer/MobileBuildMCP/workspaces/sample-0000"
}

@Suite struct SummaryTests {
    @Test func mobileBuildMCPTestRunsGiveCountsOrTheFirstFailingTest() {
        #expect(Captured.output("mobileTestsPassed").summary == .init(ok: true, detail: "3 passed"))
        #expect(Captured.output("mobileTestsFailed", isError: true).summary == .init(ok: false, detail: "1 of 3 failed · PlainTests/testConcatenation"))
        #expect(Captured.output("mobileTestsBuildFailed", isError: true).summary == .init(ok: false, detail: "build failed, tests didn't run"))
    }

    @Test func mobileBuildMCPBuildsGiveTheFirstErrorWithItsFileAndLine() {
        #expect(Captured.output("mobileBuildPassed").summary == .init(ok: true))
        #expect(Captured.output("mobileBuildFailed", isError: true).summary == .init(ok: false, detail: "MacroProbe.swift:13 cannot convert value of type 'String' to specified type 'Int'"))
    }

    @Test func anXcodeMCPFailedBuildIsAFailureThoughReportedAsANormalResult() {
        #expect(Captured.output("xcodeBuildPassed").summary == .init(ok: true))
        #expect(Captured.output("xcodeBuildFailed").summary == .init(ok: false, detail: "MacroProbe.swift:13 Cannot convert value of type 'String' to specified type 'Int'"))
    }

    @Test func xcodeMCPFailedTestsAreAFailureThoughNotReportedAsOne() {
        #expect(Captured.output("xcodeTestsPassed").summary == .init(ok: true, detail: "5 passed"))
        #expect(Captured.output("xcodeTestsFailed").summary == .init(ok: false, detail: "3 of 5 failed · MacroProbeTests/testMacro()"))
        #expect(Captured.output("xcodeTestsBuildFailed", isError: true).summary == .init(ok: false, detail: "build failed, tests didn't run"))
    }

    @Test func severalBuildErrorsAreCounted() {
        let errors = (1...3).map { #"{"classification":"error","filePath":"/a/View\#($0).swift","lineNumber":\#($0),"message":"problem \#($0)"}"# }
        let text = #"{"buildResult":"The build failed","errors":[\#(errors.joined(separator: ","))]}"#
        #expect(ToolOutput(text: text).summary == .init(ok: false, detail: "3 errors · View1.swift:1 problem 1"))
    }

    @Test func anUncapturedShapeFallsBackToWhetherTheServerReportedAnError() {
        #expect(ToolOutput(text: "something new", isError: true).summary == .init(ok: false))
        #expect(ToolOutput(text: "also new").summary == .init(ok: true))
        #expect(ToolOutput(text: #"{"unexpected":true}"#).summary == .init(ok: true))
    }

    @Test func aLongDetailIsShortenedToOneLine() {
        let text = #"{"buildResult":"The build failed","errors":[{"classification":"error","filePath":"/a/B.swift","lineNumber":1,"message":"\#(String(repeating: "x", count: 200))"}]}"#
        let detail = ToolOutput(text: text).summary.detail ?? ""
        #expect(detail.count == 100)
        #expect(detail.hasSuffix("…"))
    }

    @Test func aTestRunThatRanNoTestsIsNotASuccess() {
        #expect(Captured.output("mobileTestsNoneRan").summary == .init(ok: false, detail: "no tests ran"))
    }

    @Test func eachServerReportsHowLongTheRunItselfTook() {
        #expect(Captured.output("mobileTestsPassed").reportedDuration == 14_544)
        #expect(Captured.output("mobileTestsFailed").reportedDuration == 12_300)
        #expect(Captured.output("mobileBuildFailed").reportedDuration == 3_200)
        #expect(Captured.output("xcodeBuildPassed").reportedDuration == 3_857)
        #expect(Captured.output("xcodeTestsPassed").reportedDuration == nil)
        #expect(ToolOutput(text: "Build succeeded").reportedDuration == nil)
    }

    @Test func aTestRunSaysHowManyTestsItRan() {
        #expect(Captured.output("mobileTestsPassed").testTotal == 3)
        #expect(Captured.output("mobileTestsFailed").testTotal == 3)
        #expect(Captured.output("xcodeTestsPassed").testTotal == 5)
        #expect(Captured.output("mobileBuildPassed").testTotal == nil)
    }
}

@Suite struct FailureListTests {
    @Test func mobileBuildMCPFailingTestsAreListedOnceEachWithMessageAndPlace() {
        #expect(Captured.output("mobileTestsFailed").failures == [
            .init(title: "PlainTests/testConcatenation", message: #"XCTAssertEqual failed: ("ab") is not equal to ("ba") - strings join left to right"#, where: "PlainTests.swift:5"),
        ])
    }

    @Test func compileErrorsAreListedByFileAndLineFromEitherServer() {
        #expect(Captured.output("mobileBuildFailed").failures == [.init(title: "MacroProbe.swift:13", message: "cannot convert value of type 'String' to specified type 'Int'")])
        #expect(Captured.output("xcodeBuildFailed").failures == [.init(title: "MacroProbe.swift:13", message: "Cannot convert value of type 'String' to specified type 'Int'")])
    }

    @Test func aTestRunWhoseBuildFailedListsWhyItNeverRan() {
        let failures = Captured.output("mobileTestsBuildFailed").failures
        #expect(failures.map(\.title) == ["LLVM Profile Error", "Failed to build workspace MacroProbe with scheme MacroProbe-Package."])
        #expect(failures.last?.message.hasPrefix("Cannot test target “MacroProbeTests” on “iPhone 16”: Missing test product") == true)
    }

    @Test func theXcodeMCPFailingTestsCarryTheirOwnMessageAndLocation() {
        let expansion = "Issue recorded: Macro expansion did not produce the expected expanded source"
        #expect(Captured.output("xcodeTestsFailed").failures == [
            .init(title: "MacroProbeTests/testMacro()", message: expansion, where: "MacroProbeTests.swift:19"),
            .init(title: "MacroProbeTests/testMacroWithStringLiteral()", message: expansion, where: "MacroProbeTests.swift:35"),
            .init(title: "PlainTests/testConcatenation()", message: #"XCTAssertEqual failed: ("ab") is not equal to ("ba") - strings join left to right"#, where: "PlainTests.swift:5"),
        ])
    }

    @Test func aPassingRunHasNoFailures() {
        for name in ["mobileTestsPassed", "mobileBuildPassed", "xcodeBuildPassed", "xcodeTestsPassed"] {
            #expect(Captured.output(name).failures.isEmpty, "\(name)")
        }
    }

    @Test func anXCTFailReadsAsItsOwnMessage() {
        let text = "🧪 Test\n\nTest Failures (1):\n\n  ✗ FormatterTests / test_symbol(): failed - deliberate failure\n\n❌ 1 test failed, 0 passed, 0 skipped (⏱️ 30.7s)"
        #expect(ToolOutput(text: text).failures == [.init(title: "FormatterTests/test_symbol", message: "deliberate failure")])
    }
}

/// A failing run's text as MobileBuildMCP returns it with `showTestTiming` on: every passing test listed.
func failingRunText(passing: Int) -> String {
    (["🧪 Test", "", "Test Failures (1):", "", #"  ✗ FormatterTests / test_symbol(): XCTAssertEqual failed: ("4") is not equal to ("3")"#, "", "Test Results:"]
        + (0..<passing).map { "  ✅ FormatterTests/test_case\($0)() (0.001s)" }
        + ["  ❌ FormatterTests/test_symbol() (0.010s)", "", "❌ 1 test failed, \(passing) passed, 0 skipped (⏱️ 65.0s)", "  └ Files:",
           "     └── ~/Library/Developer/MobileBuildMCP/workspaces/sample-0000/logs/test_sim.log — Build Logs"])
        .joined(separator: "\n")
}

@Suite struct CompactionTests {
    @Test func aFailingRunKeepsItsFailuresAndSummaryAndCountsItsPassingTests() {
        #expect(ToolOutput(text: failingRunText(passing: 40)).compactTestText == [
            "🧪 Test", "", "Test Failures (1):", "", #"  ✗ FormatterTests / test_symbol(): XCTAssertEqual failed: ("4") is not equal to ("3")"#, "",
            "Test Results:", "  (40 passing tests left out; failing tests are listed in full above)", "",
            "❌ 1 test failed, 40 passed, 0 skipped (⏱️ 65.0s)", "  └ Files:",
            "     └── ~/Library/Developer/MobileBuildMCP/workspaces/sample-0000/logs/test_sim.log — Build Logs",
        ].joined(separator: "\n"))
    }

    @Test func aShortListIsLeftAsTheServerWroteIt() {
        #expect(ToolOutput(text: failingRunText(passing: 5)).compactTestText == nil)
        #expect(Captured.output("mobileBuildFailed").compactTestText == nil)
    }

    @Test func aListClaudeCodeAlreadyCutIsCountedWhole() {
        let cut = failingRunText(passing: 40).replacingOccurrences(of: "  ✅ FormatterTests/test_case20() (0.001s)", with: "\n... [71437 characters truncated] ...\n\nTests/test_case20() (0.001s)")
        let compact = ToolOutput(text: cut).compactTestText ?? ""
        #expect(compact.contains("Test Results:\n  (40 passing tests left out; failing tests are listed in full above)\n\n❌ 1 test failed, 40 passed"))
        #expect(!compact.contains("truncated"))
        #expect(!compact.contains("test_case20"))
    }

    @Test func skippedTestsKeepTheirLinesAndReasons() {
        let withSkip = failingRunText(passing: 40).replacingOccurrences(of: "  ❌ FormatterTests/test_symbol() (0.010s)", with: "  ⏭️ FormatterTests/test_skipped() (0.000s)\n      skipped: waiting on the new API\n  ❌ FormatterTests/test_symbol() (0.010s)")
        #expect(ToolOutput(text: withSkip).compactTestText?.contains("  (40 passing tests left out; failing tests are listed in full above)\n  ⏭️ FormatterTests/test_skipped() (0.000s)\n      skipped: waiting on the new API\n\n❌") == true)
    }

    @Test func aCompileErrorIsCountedOnce() {
        let cleaned = Captured.output("mobileBuildFailed").cleanBuildText ?? ""
        #expect(cleaned.contains("Errors (1):"))
        #expect(!cleaned.contains("✗ |"))
        #expect(cleaned.contains("✗ cannot convert value of type 'String' to specified type 'Int'\n    /Users/dev/MacroProbe/Sources/MacroProbe/MacroProbe.swift:13"))
        #expect(Captured.output("mobileTestsFailed").cleanBuildText == nil)
    }

    @Test func aLeftOutListIsPointedToWithoutACountOfItsOwn() throws {
        let compact = try #require(Captured.output("mobileTestsPassed").compactTestResult(savedPath: "/saved.txt"))
        let json = try #require(ToolOutput.object(compact)?["data"] as? [String: Any])
        #expect(json["testCases"] as? String == "per-test list left out to keep this result short; the counts above are complete, and the full result is in /saved.txt")
        #expect(Captured.output("mobileBuildPassed").compactTestResult(savedPath: "/saved.txt") == nil)
    }
}

@Suite struct ResultBundleTests {
    @Test func theBundleIsFoundFromEitherShapeOfResult() {
        #expect(ResultBundle.path(in: Captured.text("mobileTestsFailedUnlocated"), home: Captured.home) == "\(Captured.workspace)/result-bundles/test_sim_1.xcresult")
        #expect(ResultBundle.path(in: Captured.text("mobileTestsPassed"), home: Captured.home) == "\(Captured.workspace)/result-bundles/test_sim.xcresult")
        #expect(ResultBundle.path(in: Captured.text("mobileBuildFailed"), home: Captured.home) == nil)
    }

    @Test func aFailingTestsDetailsGiveItsFileAndLine() {
        #expect(ResultBundle.sourceLocation(details: Captured.text("xcresultFailureDetails")) == "/Users/dev/App/Tests/FormatterTests.swift:7")
        #expect(ResultBundle.sourceLocation(details: Captured.text("xcresultCrashDetails")) == nil)
        #expect(ResultBundle.sourceLocation(details: "not json") == nil)
    }

    @Test func aCrashLogGivesTheExceptionAndTopFrames() {
        #expect(ResultBundle.crashSummary(log: Captured.text("crashLog")) == [
            "crashed: EXC_BREAKPOINT (SIGTRAP)",
            "libswiftCore.dylib  closure #1 in closure #1 in _assertionFailure(_:_:file:line:flags:)",
            "libswiftCore.dylib  _assertionFailure(_:_:file:line:flags:)",
            "AppTests  implicit closure #1 in FormatterTests.test_crash()",
            "AppTests  partial apply for implicit closure #1 in FormatterTests.test_crash()",
            "libXCTestSwiftSupport.dylib  closure #1 in XCTAssertEqual<A>(_:_:_:file:line:)",
        ])
        #expect(ResultBundle.crashSummary(log: "not a crash log") == nil)
    }

    @Test func theTestListGivesEachSkippedTestAndWhy() {
        let skips = ResultBundle.skippedTests(listing: Captured.text("xcresultTestsWithSkip"))
        #expect(skips.map(\.test) == ["FormatterTests/test_skipped"])
        #expect(skips.first?.skip == .init(reason: "waiting on the new API", seconds: 0))
        #expect(ResultBundle.skippedTests(listing: "not json").isEmpty)
    }

    @Test func expectedFailuresAreNamedWithTheTrueTotal() {
        #expect(ResultBundle.expectedFailuresNote(summary: Captured.text("xcresultSummaryWithExpectedFailures"))
            == "xcrew: 2 tests also ran as expected failures (XCTExpectFailure). They count as neither passed nor failed in the result: 961 tests ran in all.")
        #expect(ResultBundle.expectedFailuresNote(summary: #"{"totalTestCount":3,"passedTests":3,"expectedFailures":0}"#) == nil)
        #expect(ResultBundle.expectedFailuresNote(summary: "not json") == nil)
    }
}

@Suite struct FailureNotesTests {
    static let crashBundle = "\(Captured.workspace)/result-bundles/test_sim_2.xcresult"

    /// The bundle of the crashed-and-skipped run, answering for its crash, its skip and its test list.
    static func crashedAndSkipped(listing: Bool = true) -> ResultBundle {
        let export = FileManager.default.temporaryDirectory.appending(path: "xcrew-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
        try? Captured.text("crashLog").write(to: export.appending(path: "crash.ips"), atomically: true, encoding: .utf8)
        let xcresulttool = "xcrun xcresulttool"
        var responses: [String: CommandResult] = [
            "\(xcresulttool) get test-results test-details --test-id FormatterTests/test_crash() --path \(crashBundle) --compact": .init(status: 0, stdout: Captured.text("xcresultCrashDetails")),
            "\(xcresulttool) export attachments --path \(crashBundle) --output-path \(export.path) --test-id FormatterTests/test_crash() --only-failures": .init(status: 0),
        ]
        if listing { responses["\(xcresulttool) get test-results tests --path \(crashBundle) --compact"] = .init(status: 0, stdout: Captured.text("xcresultTestsWithSkip")) }
        return ResultBundle(path: crashBundle, runner: FakeRunner(responses: responses), exportFolder: { export })
    }

    @Test func aFailureGetsTheLocationTheBundleRecorded() async {
        let bundle = "\(Captured.workspace)/result-bundles/test_sim_1.xcresult"
        let runner = FakeRunner(responses: [
            "xcrun xcresulttool get test-results test-details --test-id FormatterTests/test_symbol() --path \(bundle) --compact": .init(status: 0, stdout: Captured.text("xcresultFailureDetails")),
        ])
        let added = await FailureNotes.adding(to: Captured.text("mobileTestsFailedUnlocated"), from: ResultBundle(path: bundle, runner: runner))
        #expect(added.contains("failed - deliberate failure\n    /Users/dev/App/Tests/FormatterTests.swift:7"))
    }

    @Test func aCrashGetsItsExceptionAndFramesAndASkipItsReason() async {
        let added = await FailureNotes.adding(to: Captured.text("mobileTestsCrashedAndSkipped"), from: Self.crashedAndSkipped())
        #expect(added.contains("Crash: xctest at implicit closure #1 in FormatterTests.test_crash()\n      crashed: EXC_BREAKPOINT (SIGTRAP)\n      libswiftCore.dylib  closure #1 in closure #1 in _assertionFailure"))
        #expect(added.contains("  ⏭️ FormatterTests/test_skipped() (0.000s)\n      skipped: waiting on the new API"))
    }

    @Test func aSkippedTestTheTextLeftOutIsAddedFromTheBundle() async {
        let text = Captured.text("mobileTestsCrashedAndSkipped").replacingOccurrences(of: "  ⏭️ FormatterTests/test_skipped() (0.000s)\n", with: "")
        let added = await FailureNotes.adding(to: text, from: Self.crashedAndSkipped())
        #expect(added.contains("  ⏭️ FormatterTests/test_skipped() (0.000s)\n      skipped: waiting on the new API"))
    }

    @Test func aFailureTheServerLocatedIsNotLookedUp() async {
        // Every xcresulttool call would answer "not found"; the text comes back as it was.
        let text = Captured.text("mobileTestsFailed")
        #expect(await FailureNotes.adding(to: text, from: ResultBundle(path: "/b.xcresult", runner: FakeRunner())) == text)
    }
}

@Suite struct RunLogTests {
    static let preamble = "Command line invocation:\n    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -workspace /Users/dev/App/App.xcworkspace -scheme Utility\n\nTarget 'Utility' in project 'Foundation' (no dependencies)\n"
    static let compiling = "SwiftCompile normal arm64 /Users/dev/App/Sources/Utility/CurrencyFormatter.swift (in target 'Utility' from project 'Foundation')\n    cd /Users/dev/App\n"
    static let linking = "Ld /Users/dev/App/Build/Products/Debug-iphonesimulator/Utility.framework/Utility normal (in target 'Utility' from project 'Foundation')\n"
    static let signing = "CodeSign /Users/dev/App/Build/Products/Debug/MockMacros (in target 'MockMacros' from project 'Mocks')\n"
    static let otherTask = "ProcessInfoPlistFile /Users/dev/App/Build/Products/Debug-iphonesimulator/Utility.framework/Info.plist (in target 'Utility' from project 'Foundation')\n"
    static let tests = "Testing started\nTest case 'CurrencyFormatterTests.test_euroFormat()' passed on 'Clone 1 of iPhone 12 - xctest (26885)' (0.004 seconds)\nTest case 'CurrencyFormatterTests.test_poundFormat()' failed on 'Clone 1 of iPhone 12 - xctest (26885)' (0.020 seconds)\n"

    @Test func whileCompilingThePhaseNamesTheModule() {
        #expect(RunLog.phase(of: Self.preamble + Self.otherTask + Self.compiling, expectedTests: nil) == "compiling Utility")
    }

    @Test func linkingAndSigningAreNamedForTheirModule() {
        #expect(RunLog.phase(of: Self.preamble + Self.compiling + Self.linking, expectedTests: nil) == "linking Utility")
        #expect(RunLog.phase(of: Self.preamble + Self.linking + Self.signing, expectedTests: nil) == "signing MockMacros")
    }

    @Test func anyOtherTaskNamesItsModule() {
        #expect(RunLog.phase(of: Self.preamble + Self.otherTask, expectedTests: nil) == "building Utility")
    }

    @Test func onceTestsRunThePhaseCountsThem() {
        #expect(RunLog.phase(of: Self.preamble + Self.compiling + Self.tests, expectedTests: 959) == "testing 2 of 959")
        #expect(RunLog.phase(of: Self.preamble + Self.compiling + Self.tests, expectedTests: nil) == "testing · 2 done")
        #expect(RunLog.phase(of: Self.preamble + Self.compiling + "Testing started\n", expectedTests: 959) == "testing 0 of 959")
    }

    @Test func moreTestsThanLastTimeDropsTheTotal() {
        #expect(RunLog.phase(of: Self.preamble + Self.tests, expectedTests: 1) == "testing · 2 done")
    }

    @Test func aLogWithNoTaskYetSaysNothing() {
        #expect(RunLog.phase(of: Self.preamble, expectedTests: nil) == nil)
        #expect(RunLog.phase(of: "", expectedTests: nil) == nil)
    }

    @Test func theRunsLogIsTheNewestOfItsToolInThisProjectsWorkspace() throws {
        let home = Project.temporary()
        home.write("old", to: "Library/Developer/MobileBuildMCP/workspaces/App-1234/logs/test_sim_1.log")
        home.write("other tool", to: "Library/Developer/MobileBuildMCP/workspaces/App-1234/logs/build_sim_2.log")
        home.write("other project", to: "Library/Developer/MobileBuildMCP/workspaces/Other-9999/logs/test_sim_3.log")
        let logs = home.root.appending(path: "Library/Developer/MobileBuildMCP/workspaces/App-1234/logs")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: logs.appending(path: "test_sim_1.log").path)
        home.write("new", to: "Library/Developer/MobileBuildMCP/workspaces/App-1234/logs/test_sim_4.log")
        let found = RunLog.find(tool: "test_sim", since: Date(timeIntervalSince1970: 2_000), project: URL(fileURLWithPath: "/work/App"), home: home.root)
        #expect(found?.lastPathComponent == "test_sim_4.log")
        #expect(RunLog.find(tool: "test_sim", since: .distantFuture, project: URL(fileURLWithPath: "/work/App"), home: home.root) == nil)
    }
}

@Suite struct ReportTests {
    static func report(_ name: String, server: String = "MobileBuildMCP", kind: Report.Kind = .test, isError: Bool = false, runner: FakeRunner = FakeRunner()) async -> Report {
        await Report.make(server: server, kind: kind, output: Captured.output(name, isError: isError), home: Captured.home, runner: runner)
    }

    @Test func aPassingRunKeepsTheServersResult() async {
        let report = await Self.report("mobileTestsPassed")
        #expect(report == Report(ok: true, detail: "3 passed", durationMs: 14_544, tests: 3, failures: [], result: nil, notes: []))
    }

    @Test func aFailingRunCarriesItsFailuresForThePane() async {
        let report = await Self.report("mobileTestsFailed", isError: true)
        #expect(!report.ok)
        #expect(report.failures.map(\.title) == ["PlainTests/testConcatenation"])
    }

    @Test func aRunThatRanNoTestsTellsClaudeWhy() async {
        let report = await Self.report("mobileTestsNoneRan")
        #expect(report.notes == [Report.noTestsNote])
    }

    @Test func expectedFailuresReachClaudeAsANote() async {
        let runner = FakeRunner(responses: [
            "xcrun xcresulttool get test-results summary --path \(Captured.workspace)/result-bundles/test_sim.xcresult --compact": .init(status: 0, stdout: Captured.text("xcresultSummaryWithExpectedFailures")),
        ])
        let report = await Self.report("mobileTestsPassed", runner: runner)
        #expect(report.notes.first?.hasPrefix("xcrew: 2 tests also ran as expected failures") == true)
    }

    @Test func aBuildFailureReachesClaudeWithItsErrorCountedOnce() async {
        let report = await Self.report("mobileBuildFailed", kind: .build, isError: true)
        #expect(report.result?.contains("Errors (1):") == true)
    }

    @Test func aResultClaudeCodeSavedIsReadBackAndShortened() async throws {
        let folder = Project.temporary()
        folder.write(Captured.text("mobileTestsPassed"), to: "tool-results/mcp-test_sim-1.txt")
        let saved = folder.root.appending(path: "tool-results/mcp-test_sim-1.txt").path
        let notice = "Error: result (121,948 characters) exceeds maximum allowed tokens. Output has been saved to \(saved).\nFormat: JSON"
        let report = await Report.make(server: "MobileBuildMCP", kind: .test, output: ToolOutput(text: notice), home: Captured.home, runner: FakeRunner())
        #expect(report.ok)
        #expect(report.result?.contains("the full result is in \(saved)") == true)
    }

    @Test func theXcodeMCPsResultsAreNotLookedUpInABundle() async {
        let report = await Self.report("xcodeTestsFailed", server: "xcode")
        #expect(report.detail == "3 of 5 failed · MacroProbeTests/testMacro()")
        #expect(report.result == nil)
    }
}


@Suite struct TestTimeTests {
    @Test func aTestsTimeIsWrittenAsMobileBuildMCPWritesIt() {
        #expect(FailureNotes.seconds(0) == "0.000")
        #expect(FailureNotes.seconds(0.0045) == "0.005")
        #expect(FailureNotes.seconds(12.3) == "12.300")
    }
}

@Suite struct SkipListedOnceTests {
    @Test func aSkippedTestTheTextAlreadyListsGetsItsReasonAndIsNotListedAgain() async {
        let added = await FailureNotes.adding(to: Captured.text("mobileTestsCrashedAndSkipped"), from: FailureNotesTests.crashedAndSkipped())
        #expect(added.components(separatedBy: "FormatterTests/test_skipped()").count - 1 == 1)
        #expect(added.contains("  ⏭️ FormatterTests/test_skipped() (0.000s)\n      skipped: waiting on the new API"))
    }
}

@Suite struct LiveCheckFollowUpTests {
    @Test func theTestListNamesEachExpectedFailure() {
        #expect(ResultBundle.expectedFailures(listing: Captured.text("xcresultTestsWithExpectedFailures")) == ["FormatterTests/test_knownBug()", "FormatterTests/test_rounding()"])
        #expect(ResultBundle.expectedFailures(listing: "not json").isEmpty)
    }

    @Test func theExpectedFailuresNoteNamesTheTests() {
        let summary = #"{"totalTestCount":5,"passedTests":3,"expectedFailures":2}"#
        #expect(ResultBundle.expectedFailuresNote(summary: summary, names: ["A/a()", "B/b()"])
            == "xcrew: 2 tests also ran as expected failures (XCTExpectFailure): A/a() and B/b(). They count as neither passed nor failed in the result: 5 tests ran in all.")
        let many = (1...7).map { "T/t\($0)()" }
        #expect(ResultBundle.expectedFailuresNote(summary: #"{"expectedFailures":7}"#, names: many)?.contains("T/t1(), T/t2(), T/t3(), T/t4(), T/t5() and 2 more") == true)
    }

    @Test func aCrashWithoutACrashLogSaysSo() async {
        let text = Captured.text("mobileTestsCrashedAndSkipped").replacingOccurrences(of: "Crash: xctest at implicit closure #1 in FormatterTests.test_crash()", with: "Test crashed with signal trap.")
        let bundle = ResultBundle(path: "/b.xcresult", runner: FakeRunner(), exportFolder: { FileManager.default.temporaryDirectory.appending(path: "xcrew-tests-\(UUID().uuidString)") })
        let added = await FailureNotes.adding(to: text, from: bundle)
        #expect(added.contains("Test crashed with signal trap.\n      \(FailureNotes.noCrashLog)"))
    }

    @Test func doctorProblemsSaysWhenThereAreNone() {
        #expect(Doctor.problemsText(lines: []) == ["No problems."])
        #expect(Doctor.problemsText(lines: ["warn  a/b  c"]) == ["warn  a/b  c"])
    }
}
