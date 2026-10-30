import Foundation
import Testing
@testable import XcrewCLI
@testable import XcrewCore
import XcrewTestSupport

/// `xcrew look`: what a test run kept about each failed UI test's failure, from the project's newest MobileBuildMCP
/// result bundle or one named.
@Suite struct LookCommandTests {
    /// A run whose one test passed, as `xcresulttool get test-results tests` lists it.
    static let passed = #"{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"AppUITests/testLaunch()","name":"testLaunch()","result":"Passed"}]}"#

    /// A listing of these tests, each failed.
    static func failed(_ tests: [String]) -> String {
        #"{"testNodes":["# + tests.map { #"{"nodeType":"Test Case","nodeIdentifier":"\#($0)()","name":"x","result":"Failed"}"# }.joined(separator: ",") + "]}"
    }

    /// A test's activities: one run on one device, failed, with a recording when `recorded`.
    static func activities(recorded: Bool, passed: Bool = false) -> String {
        let recording = recorded ? #","attachments":[{"name":"Screen Recording.mp4","uuid":"U","lifetime":"keepAlways","timestamp":1}]"# : ""
        return #"{"testIdentifier":"T","testName":"T","testRuns":[{"device":{"deviceId":"D","deviceName":"Sim","architecture":"arm64","modelName":"iPhone 17","osVersion":"27.2"},"testPlanConfiguration":{"configurationId":"1","configurationName":"Test Scheme Action"},"activities":[{"title":"Start Test","isAssociatedWithFailure":false,"startTime":1\#(recording)},{"title":"XCTAssertTrue failed","isAssociatedWithFailure":\#(!passed),"startTime":2}]}]}"#
    }

    func context(_ responses: [String: String] = [:], project: Project = .temporary()) -> CheckContext {
        .fake(FakeRunner(responses: responses.mapValues { CommandResult(status: 0, stdout: $0) }), project: project)
    }

    static func listing(_ bundle: String) -> String { "xcrun xcresulttool get test-results tests --path \(bundle) --compact" }
    static func steps(_ test: String, _ bundle: String = "/runs/Run.xcresult") -> String { "xcrun xcresulttool get test-results activities --test-id \(test)() --path \(bundle) --compact" }

    @Test func aBundleNamedIsRead() async {
        let run = await Run("look", "--bundle", "/runs/Run.xcresult", context: context([Self.listing("/runs/Run.xcresult"): Self.passed]))
        #expect(run.status == 0)
        #expect(run.text == "xcrew: nothing failed in Run.xcresult")
    }

    /// A test named is looked at whatever the others did.
    @Test func aTestNamedIsLookedAt() async {
        let run = await Run("look", "AppUITests/testLaunch", "--bundle", "/runs/Run.xcresult", context: context([Self.steps("AppUITests/testLaunch"): Self.activities(recorded: true, passed: true)]))
        #expect(run.text == "xcrew: AppUITests/testLaunch didn't fail in Run.xcresult")
    }

    /// `Target/Suite/test`, as `-only-testing:` names a test, is the same test: the result bundle names it `Suite/test()`.
    @Test func aTestNamedWithItsTargetIsFound() async {
        let run = await Run("look", "AppUITests/LoginTests/testLogin", "--bundle", "/runs/Run.xcresult", context: context([Self.steps("LoginTests/testLogin"): Self.activities(recorded: false)]))
        #expect(run.text.hasPrefix("xcrew look: LoginTests/testLogin, in Run.xcresult\n"), "\(run.text)")
        // A run that attached nothing, as a unit test's doesn't, has no screen or hierarchy to speak of.
        #expect(!run.text.contains("screen") && !run.text.contains("on screen"), "\(run.text)")
    }

    /// When `xcresulttool` gives no answer, `look` says it couldn't read the bundle, never that nothing failed.
    @Test func aBundleThatCantBeReadIsSaidSo() async {
        let all = await Run("look", "--bundle", "/runs/Run.xcresult", context: context())
        #expect(all.text == "xcrew: couldn't read the tests in Run.xcresult; xcrun xcresulttool get test-results tests --path /runs/Run.xcresult says why")
        let one = await Run("look", "AppUITests/testLaunch", "--bundle", "/runs/Run.xcresult", context: context())
        #expect(one.text == "xcrew: couldn't read AppUITests/testLaunch's steps in Run.xcresult; xcrun xcresulttool get test-results activities --test-id AppUITests/testLaunch() --path /runs/Run.xcresult says why")
    }

    /// A failed UI test is found however many failed unit tests come before it in the listing; a test without a
    /// recording isn't a UI test's run, and isn't shown.
    @Test func aUITestIsFoundPastManyFailedUnitTests() async {
        let units = (1...12).map { "AppTests/test\($0)" }
        var responses = [Self.listing("/runs/Run.xcresult"): Self.failed(units + ["AppUITests/testLogin"]), Self.steps("AppUITests/testLogin"): Self.activities(recorded: true)]
        for unit in units { responses[Self.steps(unit)] = Self.activities(recorded: false) }
        let run = await Run("look", "--bundle", "/runs/Run.xcresult", context: context(responses))
        #expect(run.text.components(separatedBy: "\n").filter { !$0.hasPrefix(" ") } == ["xcrew look: AppUITests/testLogin, in Run.xcresult"], "\(run.text)")
    }

    /// One test at a time: a second would be dropped without a word.
    @Test func twoTestsAreAUsageError() async {
        let run = await Run("look", "AppUITests/testLaunch", "AppUITests/testLogin", "--bundle", "/runs/Run.xcresult", context: context())
        #expect(run.status == 64)
        #expect(run.errors == ["look takes one test at most (xcrew look --help)"])
    }

    /// The folder MobileBuildMCP keeps this project's result bundles in.
    static func bundles(_ project: Project) -> URL {
        project.root.appending(path: "home/Library/Developer/MobileBuildMCP/workspaces/\(RunLog.workspaceKey(root: project.root.path))/result-bundles")
    }

    /// Without a bundle named, the newest MobileBuildMCP kept for this project.
    @Test func theNewestBundleIsReadWhenNoneIsNamed() async throws {
        let project = Project.temporary()
        let bundles = Self.bundles(project)
        for name in ["test_sim_old.xcresult", "test_sim_new.xcresult"] { try FileManager.default.createDirectory(at: bundles.appending(path: name), withIntermediateDirectories: true) }
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: bundles.appending(path: "test_sim_old.xcresult").path)
        let run = await Run("look", context: context([Self.listing(bundles.appending(path: "test_sim_new.xcresult").path): Self.passed], project: project))
        #expect(run.text == "xcrew: nothing failed in test_sim_new.xcresult")
    }

    /// A run still going has no completion mark beside its bundle yet: the newest run that finished is read instead.
    @Test func aRunStillGoingIsPassedOver() async throws {
        let project = Project.temporary()
        let bundles = Self.bundles(project)
        for name in ["test_sim_done.xcresult", "test_sim_going.xcresult"] { try FileManager.default.createDirectory(at: bundles.appending(path: name), withIntermediateDirectories: true) }
        try Data().write(to: bundles.appending(path: "test_sim_done.xcresult.mobilebuildmcp-completed"))
        for name in ["test_sim_done.xcresult", "test_sim_done.xcresult.mobilebuildmcp-completed"] {
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: bundles.appending(path: name).path)
        }
        let run = await Run("look", context: context([Self.listing(bundles.appending(path: "test_sim_done.xcresult").path): Self.passed], project: project))
        #expect(run.text == "xcrew: nothing failed in test_sim_done.xcresult")
    }

    @Test func withoutABundleItSaysWhereToLook() async {
        let run = await Run("look", context: context())
        #expect(run.status == 1)
        #expect(run.text == "xcrew: MobileBuildMCP has kept no test run for this project; pass --bundle <path> for another")
    }
}
