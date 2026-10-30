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
        ToolOutput(text: text(name), server: name.hasPrefix("xcode") ? .xcode : .mobileBuildMCP, isError: isError)
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
        #expect(ToolOutput(text: text, server: .xcode).summary == .init(ok: false, detail: "3 errors · View1.swift:1 problem 1"))
    }

    @Test func anUncapturedShapeFallsBackToWhetherTheServerReportedAnError() {
        #expect(ToolOutput(text: "something new", server: .mobileBuildMCP, isError: true).summary == .init(ok: false))
        #expect(ToolOutput(text: "also new", server: .mobileBuildMCP).summary == .init(ok: true))
        #expect(ToolOutput(text: #"{"unexpected":true}"#, server: .xcode).summary == .init(ok: true))
        #expect(ToolOutput(text: #"{"unexpected":true}"#, server: .mobileBuildMCP, isError: true).summary == .init(ok: false))
    }

    @Test func eachServersOutputIsReadOnlyAsThatServers() {
        // MobileBuildMCP's wording in another server's output means nothing.
        #expect(ToolOutput(text: "❌ Build failed", server: .xcode).summary == .init(ok: true))
        #expect(ToolOutput(text: "❌ Build failed", server: .mobileBuildMCP).summary == .init(ok: false))
    }

    @Test func aFieldOfAnotherTypeLosesOnlyItself() {
        let build = #"{"buildResult":"The build failed","errors":[{"classification":"error","filePath":"/a/B.swift","lineNumber":12,"message":5}]}"#
        #expect(ToolOutput(text: build, server: .xcode).failures == [.init(title: "B.swift:12", message: "")])
        let tests = #"{"schema":"mobilebuildmcp.output.test-result","data":{"summary":{"status":"SUCCEEDED","durationMs":"soon","counts":{"passed":3,"failed":0,"skipped":0}}}}"#
        #expect(ToolOutput(text: tests, server: .mobileBuildMCP).summary == .init(ok: true, detail: "3 passed"))
        #expect(ToolOutput(text: tests, server: .mobileBuildMCP).reportedDuration == nil)
    }

    @Test func aLongDetailIsShortenedToOneLine() {
        let text = #"{"buildResult":"The build failed","errors":[{"classification":"error","filePath":"/a/B.swift","lineNumber":1,"message":"\#(String(repeating: "x", count: 200))"}]}"#
        let detail = ToolOutput(text: text, server: .xcode).summary.detail ?? ""
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
        #expect(ToolOutput(text: "Build succeeded", server: .mobileBuildMCP).reportedDuration == nil)
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
            .init(title: "PlainTests/testConcatenation", message: #"XCTAssertEqual failed: ("ab") is not equal to ("ba") - strings join left to right"#, where: "PlainTests.swift:5", isTest: true),
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
            .init(title: "MacroProbeTests/testMacro()", message: expansion, where: "MacroProbeTests.swift:19", isTest: true),
            .init(title: "MacroProbeTests/testMacroWithStringLiteral()", message: expansion, where: "MacroProbeTests.swift:35", isTest: true),
            .init(title: "PlainTests/testConcatenation()", message: #"XCTAssertEqual failed: ("ab") is not equal to ("ba") - strings join left to right"#, where: "PlainTests.swift:5", isTest: true),
        ])
    }

    /// Only a failing test can later pass: the ledger keeps tests, never compile errors.
    @Test func onlyAFailingTestIsMarkedATest() {
        #expect(Captured.output("mobileTestsFailed").failures.map(\.isTest) == [true])
        #expect(Captured.output("xcodeTestsFailed").failures.map(\.isTest) == [true, true, true])
        #expect(ToolOutput(text: "🧪 Test\n\nTest Failures (1):\n\n  ✗ FormatterTests / test_symbol(): failed - deliberate failure\n\n❌ 1 test failed, 0 passed, 0 skipped (⏱️ 30.7s)", server: .mobileBuildMCP).failures.map(\.isTest) == [true])
        for name in ["mobileBuildFailed", "xcodeBuildFailed", "mobileTestsBuildFailed"] {
            #expect(Captured.output(name).failures.allSatisfy { !$0.isTest }, "\(name)")
        }
    }

    @Test func aPassingRunHasNoFailures() {
        for name in ["mobileTestsPassed", "mobileBuildPassed", "xcodeBuildPassed", "xcodeTestsPassed"] {
            #expect(Captured.output(name).failures.isEmpty, "\(name)")
        }
    }

    @Test func anXCTFailReadsAsItsOwnMessage() {
        let text = "🧪 Test\n\nTest Failures (1):\n\n  ✗ FormatterTests / test_symbol(): failed - deliberate failure\n\n❌ 1 test failed, 0 passed, 0 skipped (⏱️ 30.7s)"
        #expect(ToolOutput(text: text, server: .mobileBuildMCP).failures == [.init(title: "FormatterTests/test_symbol", message: "deliberate failure", isTest: true)])
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
        #expect(ToolOutput(text: failingRunText(passing: 40), server: .mobileBuildMCP).compactTestText == [
            "🧪 Test", "", "Test Failures (1):", "", #"  ✗ FormatterTests / test_symbol(): XCTAssertEqual failed: ("4") is not equal to ("3")"#, "",
            "Test Results:", "  (40 passing tests left out; failing tests are listed in full above)", "",
            "❌ 1 test failed, 40 passed, 0 skipped (⏱️ 65.0s)", "  └ Files:",
            "     └── ~/Library/Developer/MobileBuildMCP/workspaces/sample-0000/logs/test_sim.log — Build Logs",
        ].joined(separator: "\n"))
    }

    @Test func aShortListIsLeftAsTheServerWroteIt() {
        #expect(ToolOutput(text: failingRunText(passing: 5), server: .mobileBuildMCP).compactTestText == nil)
        #expect(Captured.output("mobileBuildFailed").compactTestText == nil)
    }

    @Test func aListClaudeCodeAlreadyCutIsCountedWhole() {
        let cut = failingRunText(passing: 40).replacingOccurrences(of: "  ✅ FormatterTests/test_case20() (0.001s)", with: "\n... [71437 characters truncated] ...\n\nTests/test_case20() (0.001s)")
        let compact = ToolOutput(text: cut, server: .mobileBuildMCP).compactTestText ?? ""
        #expect(compact.contains("Test Results:\n  (40 passing tests left out; failing tests are listed in full above)\n\n❌ 1 test failed, 40 passed"))
        #expect(!compact.contains("truncated"))
        #expect(!compact.contains("test_case20"))
    }

    @Test func skippedTestsKeepTheirLinesAndReasons() {
        let withSkip = failingRunText(passing: 40).replacingOccurrences(of: "  ❌ FormatterTests/test_symbol() (0.010s)", with: "  ⏭️ FormatterTests/test_skipped() (0.000s)\n      skipped: waiting on the new API\n  ❌ FormatterTests/test_symbol() (0.010s)")
        #expect(ToolOutput(text: withSkip, server: .mobileBuildMCP).compactTestText?.contains("  (40 passing tests left out; failing tests are listed in full above)\n  ⏭️ FormatterTests/test_skipped() (0.000s)\n      skipped: waiting on the new API\n\n❌") == true)
    }

    @Test func aCompileErrorIsCountedOnce() {
        let cleaned = Captured.output("mobileBuildFailed").mobileText?.withoutExcerpts()?.text ?? ""
        #expect(cleaned.contains("Errors (1):"))
        #expect(!cleaned.contains("✗ |"))
        #expect(cleaned.contains("✗ cannot convert value of type 'String' to specified type 'Int'\n    /Users/dev/MacroProbe/Sources/MacroProbe/MacroProbe.swift:13"))
        #expect(Captured.output("mobileTestsFailed").mobileText?.withoutExcerpts() == nil)
    }

    @Test func aLeftOutListIsPointedToWithoutACountOfItsOwn() throws {
        let compact = try #require(Captured.output("mobileTestsPassed").compactTestResult(savedPath: "/saved.txt"))
        let json = try #require((ResultBundle.parse(compact) as? [String: Any])?["data"] as? [String: Any])
        #expect(json["testCases"] as? String == "per-test list left out to keep this result short; the counts above are complete, and the full result is in /saved.txt")
        #expect(Captured.output("mobileBuildPassed").compactTestResult(savedPath: "/saved.txt") == nil)
    }
}

@Suite struct ResultBundleTests {
    @Test func theBundleIsFoundFromEitherShapeOfResult() {
        #expect(ResultBundle.path(in: ToolOutput(text: Captured.text("mobileTestsFailedUnlocated"), server: .mobileBuildMCP), home: Captured.home) == "\(Captured.workspace)/result-bundles/test_sim_1.xcresult")
        #expect(ResultBundle.path(in: ToolOutput(text: Captured.text("mobileTestsPassed"), server: .mobileBuildMCP), home: Captured.home) == "\(Captured.workspace)/result-bundles/test_sim.xcresult")
        #expect(ResultBundle.path(in: ToolOutput(text: Captured.text("mobileBuildFailed"), server: .mobileBuildMCP), home: Captured.home) == nil)
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
        #expect(skips.map(\.test) == [TestID(suite: "FormatterTests", name: "test_skipped")])
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

    @Test func aFailureGetsTheLocationTheBundleRecorded() async throws {
        let bundle = "\(Captured.workspace)/result-bundles/test_sim_1.xcresult"
        let runner = FakeRunner(responses: [
            "xcrun xcresulttool get test-results test-details --test-id FormatterTests/test_symbol() --path \(bundle) --compact": .init(status: 0, stdout: Captured.text("xcresultFailureDetails")),
        ])
        let added = await FailureNotes.addingText(to: Captured.text("mobileTestsFailedUnlocated"), from: ResultBundle(path: bundle, runner: runner))
        #expect(added.contains("failed - deliberate failure\n    /Users/dev/App/Tests/FormatterTests.swift:7"))
        // The location lands as the failure's own location line, as if the server had written it.
        let model = await FailureNotes.adding(to: MobileText(Captured.text("mobileTestsFailedUnlocated")), from: ResultBundle(path: bundle, runner: runner))
        let failure = try #require(model?.text.lines.firstIndex { $0.failing?.test == TestID(suite: "FormatterTests", name: "test_symbol") })
        #expect(model?.text.location(after: failure)?.line == "7")
    }

    @Test func aCrashGetsItsExceptionAndFramesAndASkipItsReason() async {
        let added = await FailureNotes.addingText(to: Captured.text("mobileTestsCrashedAndSkipped"), from: Self.crashedAndSkipped())
        #expect(added.contains("Crash: xctest at implicit closure #1 in FormatterTests.test_crash()\n      crashed: EXC_BREAKPOINT (SIGTRAP)\n      libswiftCore.dylib  closure #1 in closure #1 in _assertionFailure"))
        #expect(added.contains("  ⏭️ FormatterTests/test_skipped() (0.000s)\n      skipped: waiting on the new API"))
    }

    @Test func aSkippedTestTheTextLeftOutIsAddedFromTheBundle() async {
        let text = Captured.text("mobileTestsCrashedAndSkipped").replacingOccurrences(of: "  ⏭️ FormatterTests/test_skipped() (0.000s)\n", with: "")
        let added = await FailureNotes.addingText(to: text, from: Self.crashedAndSkipped())
        #expect(added.contains("  ⏭️ FormatterTests/test_skipped() (0.000s)\n      skipped: waiting on the new API"))
    }

    @Test func aFailureTheServerLocatedIsNotLookedUp() async {
        // Every xcresulttool call would answer "not found"; the text comes back as it was.
        let text = Captured.text("mobileTestsFailed")
        #expect(await FailureNotes.addingText(to: text, from: ResultBundle(path: "/b.xcresult", runner: FakeRunner())) == text)
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
        home.write("old", to: "Library/Developer/MobileBuildMCP/workspaces/App-fc001cdb6ae6/logs/test_sim_1.log")
        home.write("other tool", to: "Library/Developer/MobileBuildMCP/workspaces/App-fc001cdb6ae6/logs/build_sim_2.log")
        home.write("other project", to: "Library/Developer/MobileBuildMCP/workspaces/Other-9999/logs/test_sim_3.log")
        let logs = home.root.appending(path: "Library/Developer/MobileBuildMCP/workspaces/App-fc001cdb6ae6/logs")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: logs.appending(path: "test_sim_1.log").path)
        home.write("new", to: "Library/Developer/MobileBuildMCP/workspaces/App-fc001cdb6ae6/logs/test_sim_4.log")
        let found = RunLog.find(tool: "test_sim", since: Date(timeIntervalSince1970: 2_000), project: URL(fileURLWithPath: "/work/App"), home: home.root)
        #expect(found?.lastPathComponent == "test_sim_4.log")
        #expect(RunLog.find(tool: "test_sim", since: .distantFuture, project: URL(fileURLWithPath: "/work/App"), home: home.root) == nil)
    }
}

@Suite struct ReportTests {
    static func report(_ name: String, kind: Report.Kind = .test, isError: Bool = false, runner: FakeRunner = FakeRunner()) async -> Report {
        await Report.make(kind: kind, output: Captured.output(name, isError: isError), home: Captured.home, runner: runner)
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
        let saved = SavedResultTests.saved()
        let notice = "Error: result (121,948 characters) exceeds maximum allowed tokens. Output has been saved to \(saved).\nFormat: JSON"
        let report = await Report.make(kind: .test, output: ToolOutput(text: notice, server: .mobileBuildMCP), home: Captured.home, runner: FakeRunner())
        #expect(report.ok)
        #expect(report.result?.contains("the full result is in \(saved)") == true)
    }

    @Test func theXcodeMCPsResultsAreNotLookedUpInABundle() async {
        let report = await Self.report("xcodeTestsFailed")
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
        let added = await FailureNotes.addingText(to: Captured.text("mobileTestsCrashedAndSkipped"), from: FailureNotesTests.crashedAndSkipped())
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
        let added = await FailureNotes.addingText(to: text, from: bundle)
        #expect(added.contains("Test crashed with signal trap.\n      \(FailureNotes.noCrashLog)"))
    }

    @Test func doctorProblemsSaysWhenThereAreNone() {
        #expect(Doctor.problemsText(lines: []) == ["No problems."])
        #expect(Doctor.problemsText(lines: ["warn  a/b  c"]) == ["warn  a/b  c"])
    }
}

@Suite struct RunLogWorkspaceTests {
    static let workspaces = "Library/Developer/MobileBuildMCP/workspaces"

    /// MobileBuildMCP's own key: its folder name made safe, then the first 12 hex of the SHA-256 of the root
    /// (`shasum -a 256` of each path).
    @Test func theWorkspaceIsNamedAsMobileBuildMCPNamesIt() {
        #expect(RunLog.workspaceKey(root: "/work/one/App") == "App-720d05200789")
        #expect(RunLog.workspaceKey(root: "/work/My App (2)") == "My-App-2-72c675102e34")
        #expect(RunLog.workspaceKey(root: "/") == "workspace-8a5edab28263")
        // A decomposed accent, as macOS often stores one: MobileBuildMCP's JavaScript keeps the `e` and drops the mark.
        #expect(RunLog.workspaceKey(root: "/work/Cafe\u{301}") == "Cafe-0daa8a117d35")
    }

    /// Two checkouts of folders with one name each have a workspace; only this one's is followed.
    @Test func aCheckoutOfAnotherFolderWithTheSameNameIsNotFollowed() throws {
        let home = Project.temporary()
        home.write("mine", to: "\(Self.workspaces)/App-720d05200789/logs/test_sim_1_pid100_a.log")
        home.write("theirs", to: "\(Self.workspaces)/App-4c3117e2da91/logs/test_sim_2_pid200_b.log")
        try Self.age("App-720d05200789/logs/test_sim_1_pid100_a.log", in: home, to: 2_000)
        let found = RunLog.find(tool: "test_sim", since: Date(timeIntervalSince1970: 1_000), project: URL(fileURLWithPath: "/work/one/App"), home: home.root)
        #expect(found?.lastPathComponent == "test_sim_1_pid100_a.log")
    }

    /// Two sessions in one checkout write into one workspace; each follows only its own server's log.
    @Test func anotherSessionsLogIsNotFollowed() throws {
        let home = Project.temporary()
        home.write("mine", to: "\(Self.workspaces)/App-720d05200789/logs/test_sim_1_pid100_a.log")
        home.write("theirs", to: "\(Self.workspaces)/App-720d05200789/logs/test_sim_2_pid200_b.log")
        try Self.age("App-720d05200789/logs/test_sim_1_pid100_a.log", in: home, to: 2_000)
        let project = URL(fileURLWithPath: "/work/one/App")
        #expect(RunLog.find(tool: "test_sim", since: Date(timeIntervalSince1970: 1_000), project: project, home: home.root, servers: [100])?.lastPathComponent == "test_sim_1_pid100_a.log")
        // Without a session to read servers from, as from a terminal, or with none recognised in it, the newest is the run's.
        #expect(RunLog.find(tool: "test_sim", since: Date(timeIntervalSince1970: 1_000), project: project, home: home.root)?.lastPathComponent == "test_sim_2_pid200_b.log")
        #expect(RunLog.find(tool: "test_sim", since: Date(timeIntervalSince1970: 1_000), project: project, home: home.root, servers: [])?.lastPathComponent == "test_sim_2_pid200_b.log")
    }

    /// Without its config MobileBuildMCP keys the workspace by the real path, as Node's `realpath` gives it, `/private`
    /// included; with it, by the path as found. The expected key comes from `realpath` and `shasum`.
    @Test func aProjectReachedThroughALinkIsFollowedByEitherPath() async throws {
        let home = Project.temporary()
        let real = home.root.appending(path: "real/App")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = home.root.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: home.root.appending(path: "real"))
        let realpath = await SystemCommandRunner().run(["/bin/realpath", link.appending(path: "App").path], stdin: nil, timeout: .seconds(10)).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(realpath.hasPrefix("/private/"))
        let hash = await SystemCommandRunner().run(["/usr/bin/shasum", "-a", "256"], stdin: Data(realpath.utf8), timeout: .seconds(10)).stdout.prefix(12)
        let key = "App-\(hash)"
        home.write("mine", to: "\(Self.workspaces)/\(key)/logs/test_sim_1_pid100_a.log")
        #expect(RunLog.find(tool: "test_sim", since: .distantPast, project: link.appending(path: "App"), home: home.root)?.lastPathComponent == "test_sim_1_pid100_a.log")
    }

    /// MobileBuildMCP's install, from its command on the PATH: `<prefix>/bin/mobilebuildmcp`, beside `<prefix>/libexec`.
    static var mobileBuildMCP: URL? {
        SystemCommandRunner().which("mobilebuildmcp").map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().appending(path: "libexec") }
    }

    /// The key is MobileBuildMCP's own derivation, so it's checked against the installed one wherever MobileBuildMCP
    /// is installed (this Mac, the weekly canary), run with the Node it ships.
    @Test(.enabled(if: mobileBuildMCP != nil))
    func theWorkspaceKeyIsTheInstalledMobileBuildMCPs() async throws {
        let libexec = try #require(Self.mobileBuildMCP)
        let source = libexec.appending(path: "build/utils/workspace-identity.js")
        for root in ["/work/one/App", "/work/My App (2)", "/", "/work/Cafe\u{301}"] {
            let script = "import(process.argv[1]).then(m => console.log(m.workspaceKeyForRoot(process.argv[2])))"
            let ran = await SystemCommandRunner().run([libexec.appending(path: "node-runtime").path, "-e", script, source.path, root], stdin: nil, timeout: .seconds(30))
            let upstream = ran.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(upstream == RunLog.workspaceKey(root: root), "MobileBuildMCP's workspaceKeyForRoot in build/utils/workspace-identity.js names \(root)'s workspace \(upstream), not \(RunLog.workspaceKey(root: root)): RunLog.workspaceKey has to follow it (\(ran.stderr))")
        }
        let capture = try String(contentsOf: libexec.appending(path: "build/utils/xcodebuild-log-capture.js"), encoding: .utf8)
        #expect(capture.contains("_pid${process.pid}_"), "MobileBuildMCP's build/utils/xcodebuild-log-capture.js no longer names a log with _pid<server pid>_: RunLog.find's session filter has to follow it")
    }

    static func age(_ path: String, in home: Project, to seconds: TimeInterval) throws {
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: seconds)], ofItemAtPath: home.root.appending(path: "\(workspaces)/\(path)").path)
    }

    @Test func anotherProjectWhoseNameStartsTheSameIsNotFollowed() {
        let home = Project.temporary()
        home.write("legacy", to: "Library/Developer/MobileBuildMCP/workspaces/App-Legacy-0a1b2c3d4e5f/logs/test_sim_2.log")
        #expect(RunLog.find(tool: "test_sim", since: .distantPast, project: URL(fileURLWithPath: "/work/App"), home: home.root) == nil)
        home.write("mine", to: "Library/Developer/MobileBuildMCP/workspaces/App-fc001cdb6ae6/logs/test_sim_1.log")
        #expect(RunLog.find(tool: "test_sim", since: .distantPast, project: URL(fileURLWithPath: "/work/App"), home: home.root)?.lastPathComponent == "test_sim_1.log")
    }
}

@Suite struct LookupConcurrencyTests {
    /// Answers each xcresulttool call after a short wait, and records the most it saw at once.
    final class SlowRunner: CommandRunning, @unchecked Sendable {
        private let lock = NSLock()
        private var running = 0
        private var peak = 0
        var mostAtOnce: Int { lock.withLock { peak } }

        func run(_ argv: [String], stdin: Data?, timeout: Duration) async -> CommandResult {
            lock.withLock { running += 1; peak = max(peak, running) }
            try? await Task.sleep(for: .milliseconds(30))
            lock.withLock { running -= 1 }
            return CommandResult(status: 0, stdout: "{}")
        }

        func which(_ name: String) -> String? { nil }
    }

    @Test func aRunWithManyFailuresLooksThemUpAFewAtATime() async {
        let failures = (1...10).map { "  ✗ Suite / test_\($0)(): failed\n" }.joined(separator: "\n")
        let text = "🧪 Test\n\nTest Failures (10):\n\n\(failures)\n❌ 10 tests failed, 0 passed, 0 skipped (⏱️ 1.0s)"
        let runner = SlowRunner()
        _ = await FailureNotes.addingText(to: text, from: ResultBundle(path: "/b.xcresult", runner: runner))
        #expect(runner.mostAtOnce > 1)
        #expect(runner.mostAtOnce <= FailureNotes.mostAtOnce)
    }
}

@Suite struct RunLogTailTests {
    @Test func aStepBeforeALongStretchWithoutTasksIsFound() throws {
        let project = Project.temporary()
        let warnings = String(repeating: "ld: warning: object file was built for a newer iOS Simulator version\n", count: 2_000)
        project.write("SwiftCompile normal arm64 /w/A.swift (in target 'Early' from project 'App')\nSwiftCompile normal arm64 /w/B.swift (in target 'Payments' from project 'App')\n" + warnings, to: "build.log")
        #expect(RunLog.phase(ofLogAt: project.root.appending(path: "build.log"), expectedTests: nil) == "compiling Payments")
    }

    @Test func aLogWithNoTaskAnywhereSaysNothing() throws {
        let project = Project.temporary()
        project.write(String(repeating: "note: nothing to do\n", count: 5_000), to: "build.log")
        #expect(RunLog.phase(ofLogAt: project.root.appending(path: "build.log"), expectedTests: nil) == nil)
    }
}

extension FailureNotes {
    /// The notes on a text as text, as the assertions above read them.
    static func addingText(to text: String, from bundle: ResultBundle, keepingImagesIn images: URL? = nil) async -> String {
        await adding(to: MobileText(text), from: bundle, keepingImagesIn: images)?.text.text ?? text
    }
}

/// Each case is a report main's binary wrote differently from a first version of the typed model.
@Suite struct SameAsBeforeTests {
    static let listingPath = "/b.xcresult"

    static func bundle(listing: String) -> ResultBundle {
        ResultBundle(path: listingPath, runner: FakeRunner(responses: [
            "xcrun xcresulttool get test-results tests --path \(listingPath) --compact": .init(status: 0, stdout: listing),
        ]))
    }

    @Test func notesWithNowhereToGoLeaveTheTextAsItWas() async {
        // A skipped test the text leaves out goes before the summary line; with none, nothing is added.
        let text = MobileText("🧪 Test\n\nTest Results:\n  ⏭️ OtherTests/test_other() (0.000s)\n")
        #expect(await FailureNotes.adding(to: text, from: Self.bundle(listing: Captured.text("xcresultTestsWithSkip"))) == nil)
    }

    @Test func aNoteOfSeveralLinesIsReadAsSeveralLines() async throws {
        let listing = Captured.text("xcresultTestsWithSkip").replacingOccurrences(of: "waiting on the new API", with: #"waiting\nsee the ticket"#)
        let text = MobileText(Captured.text("mobileTestsCrashedAndSkipped"))
        let added = try #require(await FailureNotes.adding(to: text, from: Self.bundle(listing: listing))).text
        #expect(added.lines.map(\.text) == MobileText(added.text).lines.map(\.text))
    }

    @Test func anXcodeLineNumberIsWrittenWhateverItsType() {
        let build = { (line: String) in #"{"buildResult":"failed","errors":[{"classification":"error","filePath":"/a/B.swift","lineNumber":\#(line),"message":"problem"}]}"# }
        #expect(ToolOutput(text: build(#""12""#), server: .xcode).failures.first?.title == "B.swift:12")
        #expect(ToolOutput(text: build("12"), server: .xcode).failures.first?.title == "B.swift:12")
        #expect(ToolOutput(text: build("null"), server: .xcode).failures.first?.title == "B.swift:<null>")
    }

    @Test func anXcodeErrorWhoseDataIsNotTextStillSaysWhatFailed() {
        #expect(ToolOutput(text: #"{"type":"error","data":{"message":"Build action failed"}}"#, server: .xcode).summary == .init(ok: false, detail: "build failed, tests didn't run"))
        #expect(ToolOutput(text: #"{"type":"error","data":5}"#, server: .xcode).summary == .init(ok: false, detail: "5"))
    }

    @Test func onlyATestRunsTextIsCompacted() {
        let passing = (1...30).map { "  ✅ Suite/test_\($0)() (0.001s)" }.joined(separator: "\n")
        let text = "🧪 Something else\n\nTest Results:\n\(passing)\n\n❌ 1 test failed, 30 passed, 0 skipped (⏱️ 1.0s)"
        #expect(ToolOutput(text: text, server: .mobileBuildMCP).compactTestText == nil)
    }

    @Test func aDurationTooLargeForAnIntIsLeftOut() {
        let text = #"{"schema":"mobilebuildmcp.output.build-result","data":{"summary":{"status":"SUCCEEDED","durationMs":1e300}}}"#
        #expect(ToolOutput(text: text, server: .mobileBuildMCP).reportedDuration == nil)
    }

    @Test func mobileBuildMCPJSONWithoutItsSchemaStillCountsItsTests() {
        let text = #"{"data":{"summary":{"counts":{"passed":3,"failed":0,"skipped":1}}}}"#
        #expect(ToolOutput(text: text, server: .mobileBuildMCP).testTotal == 4)
    }
}

@Suite struct RepeatedWarningTests {
    static let message = "'oldAPI()' is deprecated: use newAPI() instead, which handles every locale and time zone the old one quietly ignored [#DeprecatedDeclaration]"

    /// The captured text or JSON with the message of each warning from the `from`th on replaced by its own.
    static func distinct(_ name: String, from: Int = 0) -> String {
        let parts = Captured.text(name).components(separatedBy: message)
        return parts.dropFirst().enumerated().reduce(parts[0]) { text, part in
            text + (part.offset < from ? message : "another warning \(part.offset)") + part.element
        }
    }

    static func report(_ text: String) async -> Report {
        await Report.make(kind: .test, output: ToolOutput(text: text, server: .mobileBuildMCP), home: Captured.home, runner: FakeRunner())
    }

    @Test func aRepeatedWarningInTheTextIsListedOnceWithItsCountAndEveryPlace() async throws {
        let result = try #require(await ReportTests.report("mobileTestsPassedWithWarnings").result)
        #expect(result.count < Captured.text("mobileTestsPassedWithWarnings").count)
        #expect(result.contains("Warnings (3):\n\n  ⚠ \(Self.message) (3×, /Users/dev/Warn/Sources/Warn/Warn.swift:4, :5, :6)\n\n✅ 1 test passed, 0 failed, 0 skipped (⏱️ 8.0s)"))
    }

    @Test func aRepeatedWarningInTheJSONIsListedOnceWithItsCountAndEveryPlace() async throws {
        let result = try #require(await ReportTests.report("mobileTestsPassedWithWarningsJSON").result)
        #expect(result.count < Captured.text("mobileTestsPassedWithWarningsJSON").count)
        let data = try #require((ResultBundle.parse(result) as? [String: Any])?["data"] as? [String: Any])
        let warnings = try #require((data["diagnostics"] as? [String: Any])?["warnings"] as? [[String: Any]])
        #expect(warnings.count == 1)
        #expect(warnings.first?["message"] as? String == Self.message)
        #expect(warnings.first?["count"] as? Int == 3)
        #expect(warnings.first?["location"] as? String == "/Users/dev/Warn/Sources/Warn/Warn.swift:4, :5, :6")
        #expect((data["summary"] as? [String: Any])?["status"] as? String == "SUCCEEDED")
    }

    @Test func distinctWarningsAreLeftAsTheServerWroteThem() async {
        #expect(await Self.report(Self.distinct("mobileTestsPassedWithWarnings")).result == nil)
        #expect(await Self.report(Self.distinct("mobileTestsPassedWithWarningsJSON")).result == nil)
    }

    @Test func aWarningListedOnceKeepsItsOwnLinesBesideARepeatedOne() async throws {
        let text = try #require(await Self.report(Self.distinct("mobileTestsPassedWithWarnings", from: 2)).result)
        #expect(text.contains("  ⚠ \(Self.message) (2×, /Users/dev/Warn/Sources/Warn/Warn.swift:4, :5)\n\n  ⚠ another warning 2\n    /Users/dev/Warn/Sources/Warn/Warn.swift:6\n\n✅"))
        let json = try #require(await Self.report(Self.distinct("mobileTestsPassedWithWarningsJSON", from: 2)).result)
        let warnings = try #require(((ResultBundle.parse(json) as? [String: Any])?["data"] as? [String: Any]).flatMap { ($0["diagnostics"] as? [String: Any])?["warnings"] as? [[String: Any]] })
        #expect(warnings.map { $0["location"] as? String } == ["/Users/dev/Warn/Sources/Warn/Warn.swift:4, :5", "/Users/dev/Warn/Sources/Warn/Warn.swift:6"])
        #expect(warnings.last?["count"] == nil)
    }

    @Test func aPathWithASpaceKeepsItsPlaces() async throws {
        let text = Captured.text("mobileTestsPassedWithWarnings").replacingOccurrences(of: "/Users/dev/Warn/", with: "/Users/dev/My Warn/")
        let result = try #require(await Self.report(text).result)
        #expect(result.contains("(3×, /Users/dev/My Warn/Sources/Warn/Warn.swift:4, :5, :6)\n\n✅"))
    }

    @Test func aSavedResultTheCollapseAloneWouldEditStaysSaved() async {
        let saved = SavedResultTests.saved(Captured.text("mobileTestsPassedWithWarningsJSON").replacingOccurrences(of: "output.test-result", with: "output.build-result"), as: "mcp-build_macos-1.txt")
        let notice = "Error: result (121,948 characters) exceeds maximum allowed tokens. Output has been saved to \(saved).\nFormat: JSON"
        let report = await Report.make(kind: .build, output: ToolOutput(text: notice, server: .mobileBuildMCP), home: Captured.home, runner: FakeRunner())
        #expect(report.ok)
        #expect(report.result == nil)
    }

    @Test func aColumnStaysWithItsLine() {
        #expect(RepeatedWarnings.locations(["/a/A.swift:4:12", "/a/A.swift:4:30", "/a/A.swift:9"].map(RepeatedWarnings.Location.init)) == "/a/A.swift:4:12, :4:30, :9")
    }

    @Test func aPlaceListedTwiceIsListedOnce() {
        let warning = RepeatedWarnings.Warning(message: "m", location: RepeatedWarnings.Location("/a/A.swift:4"))
        #expect(RepeatedWarnings.grouped([warning, warning])?.first.map(RepeatedWarnings.line) == "m (2×, /a/A.swift:4)")
    }

    @Test func eachFilesPathIsWrittenOnceBeforeItsLines() {
        #expect(RepeatedWarnings.locations(["/a/A.swift:4", "/a/A.swift:5", "/b/B.swift:9", "/a/A.swift:7", "/c/C.swift"].map(RepeatedWarnings.Location.init)) == "/a/A.swift:4, :5, /b/B.swift:9, /a/A.swift:7, /c/C.swift")
    }
}

@Suite struct SavedResultTests {
    /// A result Claude Code saved, at `<config>/projects/<project>/<session>/tool-results/<name>`, `config` in `folder`.
    static func saved(_ text: String = Captured.text("mobileTestsPassed"), as name: String = "mcp-test_sim-1.txt", in folder: String = "claude") -> String {
        let root = Project.temporary()
        let path = "\(folder)/projects/-work-App/0b6e4c1a/tool-results/\(name)"
        root.write(text, to: path)
        return root.root.appending(path: path).path
    }

    @Test func aNoticeInOtherWordsStillLeadsToTheFile() async {
        let path = Self.saved()
        for notice in ["Result too large; written to \(path) (JSON).", "Saved the full output at \(path)", "Error: output exceeded the limit. See '\(path)'.", "Output has been saved to \(path).\nFormat: JSON", "Output saved to `\(path)`", "Saved: <\(path)>", "Saved to “\(path)”."] {
            #expect(Report.savedPath(notice) == path, "\(notice)")
        }
        let report = await Report.make(kind: .test, output: ToolOutput(text: "Result too large; written to \(path) (JSON).", server: .mobileBuildMCP), home: Captured.home, runner: FakeRunner())
        #expect(report.result?.contains("the full result is in \(path)") == true)
    }

    @Test func aPathToNoFileIsNotASavedResult() {
        #expect(Report.savedPath("Output has been saved to /nowhere/tool-results/mcp-test_sim-1.txt.\nFormat: JSON") == nil)
    }

    @Test func aLongResultThatNamesASavedFileIsNotANotice() {
        let path = Self.saved()
        #expect(Report.savedPath("Output has been saved to \(path).\n" + String(repeating: "✅ FormatterTests/test_case() (0.001s)\n", count: 300)) == nil)
    }

    @Test func aPathOutsideAToolResultsFolderIsNotASavedResult() {
        let folder = Project.temporary()
        folder.write("{}", to: "logs/test_sim.log")
        #expect(Report.savedPath("Output has been saved to \(folder.root.appending(path: "logs/test_sim.log").path).") == nil)
    }

    /// A path with a space in it is cut there, as it always was: the notice doesn't quote its path.
    @Test func aConfigFolderWithParenthesesOrAnApostropheIsFound() {
        let path = Self.saved(in: "o'neil(2)/.claude")
        #expect(Report.savedPath("Output has been saved to \(path).\nFormat: JSON") == path)
    }

    @Test func aProjectsOwnToolResultsFolderIsNotASavedResult() {
        let folder = Project.temporary()
        folder.write("struct Parser {}", to: "App/tool-results/Parser.swift")
        #expect(Report.savedPath("Compiling \(folder.root.appending(path: "App/tool-results/Parser.swift").path)\n❌ Build failed") == nil)
    }

    @Test func aFolderIsNotASavedResult() {
        let path = Self.saved()
        let folder = URL(fileURLWithPath: path).deletingLastPathComponent().appending(path: "session-abc")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(Report.savedPath("Output has been saved to \(folder.path).") == nil)
    }
}

/// A test run with `-test-iterations` records each run of each test as a `Repetition`: a test that failed some runs and
/// passed others is flaky, one that failed every run is a real failure (docs/findings.md, *Flaky or real*).
@Suite struct RepetitionTests {
    static let listing = """
        {"testNodes":[{"nodeType":"Unit test bundle","name":"AppTests","children":[{"nodeType":"Test Suite","name":"RepetitionTests","children":[
          {"nodeType":"Test Case","nodeIdentifier":"RepetitionTests/testMixed()","name":"testMixed()","result":"Failed","children":[
            {"nodeType":"Repetition","name":"Repetition 1","result":"Passed"},{"nodeType":"Repetition","name":"Repetition 2","result":"Failed"},{"nodeType":"Repetition","name":"Repetition 3","result":"Passed"}]},
          {"nodeType":"Test Case","nodeIdentifier":"RepetitionTests/testAlways()","name":"testAlways()","result":"Failed","children":[
            {"nodeType":"Repetition","name":"Repetition 1","result":"Failed"},{"nodeType":"Repetition","name":"Repetition 2","result":"Failed"},{"nodeType":"Repetition","name":"Repetition 3","result":"Failed"}]},
          {"nodeType":"Test Case","nodeIdentifier":"RepetitionTests/testNever()","name":"testNever()","result":"Passed","children":[
            {"nodeType":"Repetition","name":"Repetition 1","result":"Passed"},{"nodeType":"Repetition","name":"Repetition 2","result":"Passed"},{"nodeType":"Repetition","name":"Repetition 3","result":"Passed"}]},
          {"nodeType":"Test Case","nodeIdentifier":"RepetitionTests/testOnce()","name":"testOnce()","result":"Passed"}]}]}]}
        """

    @Test func eachRepeatedTestCountsItsFailedRuns() {
        let found = ResultBundle.repetitions(listing: Self.listing)
        #expect(found.map { "\($0.test) \($0.failed)/\($0.runs) \($0.verdict)" } == ["RepetitionTests/testMixed 1/3 flaky", "RepetitionTests/testAlways 3/3 real", "RepetitionTests/testNever 0/3 passed"])
    }

    @Test func theNoteGivesEachTestItsVerdict() {
        let note = ResultBundle.repetitionsNote(ResultBundle.repetitions(listing: Self.listing))
        #expect(note == "xcrew: across 3 runs each: RepetitionTests/testMixed is flaky, failing 1 of 3; RepetitionTests/testAlways failed every run, a real failure. 1 more passed every run.")
    }

    @Test func aRunWithoutRepetitionsHasNoNote() {
        #expect(ResultBundle.repetitionsNote(ResultBundle.repetitions(listing: #"{"testNodes":[]}"#)) == nil)
    }
}

/// A run the mod knows was repeated reads each test's runs from the bundle: the verdicts reach Claude, and the counts
/// the mod keeps.
@Suite struct RepeatedRunReportTests {
    static let bundle = "\(Captured.workspace)/result-bundles/test_sim.xcresult"

    func runner() -> FakeRunner {
        FakeRunner(responses: [
            "xcrun xcresulttool get test-results tests --path \(Self.bundle) --compact": .init(status: 0, stdout: RepetitionTests.listing),
            "xcrun xcresulttool get test-results summary --path \(Self.bundle) --compact": .init(status: 0, stdout: #"{"totalTestCount":4,"passedTests":2,"failedTests":2,"expectedFailures":0}"#),
        ])
    }

    @Test func aRepeatedRunGivesEachTestItsVerdict() async {
        let report = await Report.make(kind: .test, output: ToolOutput(text: Captured.text("mobileTestsPassed"), server: .mobileBuildMCP), home: Captured.home, runner: runner(), repeated: true)
        #expect(report.notes.contains { $0.contains("RepetitionTests/testMixed is flaky, failing 1 of 3") })
        #expect(report.repeated?.map(\.verdict) == [.flaky, .real, .passed])
    }

    /// The list is asked for only when the run was repeated: every other test run keeps its one fewer call.
    @Test func aRunNotRepeatedReadsNoRepetitions() async {
        let report = await Report.make(kind: .test, output: ToolOutput(text: Captured.text("mobileTestsPassed"), server: .mobileBuildMCP), home: Captured.home, runner: runner())
        #expect(report.repeated == nil)
        #expect(!report.notes.contains { $0.contains("flaky") })
    }
}

/// What the first reading of repetitions got wrong.
@Suite struct RepetitionEdgeTests {
    func testCase(_ name: String, _ children: String) -> String {
        #"{"nodeType":"Test Case","nodeIdentifier":"S/\#(name)()","name":"\#(name)()","result":"Failed","children":[\#(children)]}"#
    }

    func repetitions(_ results: [String]) -> String {
        results.enumerated().map { #"{"nodeType":"Repetition","name":"Repetition \#($0.offset + 1)","result":"\#($0.element)"}"# }.joined(separator: ",")
    }

    func listing(_ cases: [String]) -> String {
        #"{"testNodes":[{"nodeType":"Test Suite","name":"S","children":[\#(cases.joined(separator: ","))]}]}"#
    }

    /// A skipped run is no pass: a test skipped every run has no verdict, not "passed every run".
    @Test func aSkippedRunIsNoPass() {
        let found = ResultBundle.repetitions(listing: listing([testCase("testSkipped", repetitions(["Skipped", "Skipped", "Skipped"]))]))
        #expect(found.map(\.verdict) == [.none])
    }

    /// A parameterized Swift Testing test holds its runs under each argument.
    @Test func runsUnderEachArgumentCount() {
        let arguments = #"{"nodeType":"Arguments","name":"1","children":[\#(repetitions(["Passed", "Failed"]))]},{"nodeType":"Arguments","name":"2","children":[\#(repetitions(["Passed", "Passed"]))]}"#
        let found = ResultBundle.repetitions(listing: listing([testCase("testParameterized", arguments)]))
        #expect(found.map { "\($0.failed)/\($0.runs) \($0.verdict)" } == ["1/4 flaky"])
    }

    /// The note names the tests that need a decision, and only a few of them: a whole target repeated mustn't flood it.
    @Test func theNoteNamesAFewAndCountsTheRest() {
        let cases = (1...8).map { testCase("testFlaky\($0)", repetitions(["Passed", "Failed"])) } + (1...30).map { testCase("testFine\($0)", repetitions(["Passed", "Passed"])) }
        let note = ResultBundle.repetitionsNote(ResultBundle.repetitions(listing: listing(cases))) ?? ""
        #expect(note.contains("S/testFlaky5 is flaky") && !note.contains("S/testFlaky6"))
        #expect(note.contains("and 3 more flaky or failing"))
        #expect(note.contains("30 more passed every run"))
        #expect(!note.contains("testFine"))
    }

    /// A run repeated whose bundle can't be read says it has no verdict, rather than nothing.
    @Test func aRepeatedRunWithoutABundleSaysSo() async {
        let report = await Report.make(kind: .test, output: ToolOutput(text: Captured.text("mobileTestsPassed"), server: .mobileBuildMCP), home: Captured.home, runner: FakeRunner(), repeated: true)
        #expect(report.notes.contains { $0.contains("no verdict on which tests are flaky") })
    }
}
