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

    func context(_ project: Project = .temporary(), listing bundles: [String] = []) -> CheckContext {
        var responses: [String: CommandResult] = [:]
        for bundle in bundles { responses["xcrun xcresulttool get test-results tests --path \(bundle) --compact"] = CommandResult(status: 0, stdout: Self.passed) }
        return .fake(FakeRunner(responses: responses), project: project)
    }

    @Test func aBundleNamedIsRead() async {
        let run = await Run("look", "--bundle", "/runs/Run.xcresult", context: context(listing: ["/runs/Run.xcresult"]))
        #expect(run.status == 0)
        #expect(run.text == "xcrew: nothing failed in Run.xcresult")
    }

    /// A test named is looked at whatever the others did.
    @Test func aTestNamedIsLookedAt() async {
        let run = await Run("look", "AppUITests/testLaunch", "--bundle", "/runs/Run.xcresult", context: context(listing: ["/runs/Run.xcresult"]))
        #expect(run.text == "xcrew: AppUITests/testLaunch didn't fail in Run.xcresult")
    }

    /// Without a bundle named, the newest MobileBuildMCP kept for this project.
    @Test func theNewestBundleIsReadWhenNoneIsNamed() async throws {
        let project = Project.temporary()
        let home = project.root.appending(path: "home")
        let bundles = home.appending(path: "Library/Developer/MobileBuildMCP/workspaces/\(RunLog.workspaceKey(root: project.root.path))/result-bundles")
        for name in ["test_sim_old.xcresult", "test_sim_new.xcresult"] { try FileManager.default.createDirectory(at: bundles.appending(path: name), withIntermediateDirectories: true) }
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: bundles.appending(path: "test_sim_old.xcresult").path)
        let run = await Run("look", context: context(project, listing: [bundles.appending(path: "test_sim_new.xcresult").path]))
        #expect(run.text == "xcrew: nothing failed in test_sim_new.xcresult")
    }

    /// One test at a time: a second would be dropped without a word.
    @Test func twoTestsAreAUsageError() async {
        let run = await Run("look", "AppUITests/testLaunch", "AppUITests/testLogin", "--bundle", "/runs/Run.xcresult", context: context(listing: ["/runs/Run.xcresult"]))
        #expect(run.status == 64)
        #expect(run.errors == ["look takes one test at most (xcrew look --help)"])
    }

    @Test func withoutABundleItSaysWhereToLook() async {
        let run = await Run("look", context: context())
        #expect(run.status == 1)
        #expect(run.text == "xcrew: MobileBuildMCP has kept no test run for this project; pass --bundle <path> for another")
    }
}
