import Foundation
import Testing
import XcrewTestSupport
@testable import XcrewCore

/// The elements on screen at each failed run's failure, as `look` lists them under each run.
@Suite struct LookElementsTests {
    static let elements = ["on screen:", #"  Application "App""#, #"    Button "Continue", identifier "continue""#]

    /// Under a test plan of three configurations whose screens hold the same elements, the list shows once, and each
    /// later configuration says it's the same in one line; a run whose elements differ lists its own.
    @Test func elementsTheSameAsAnEarlierRunsAreSaidOnce() {
        let other = ["on screen:", #"  Application "App""#, #"    StaticText "Plan B""#]
        let runs: [(String, [String]?)] = [("Plan A · iPhone 18, iOS 27.2", Self.elements), ("Plan B · iPhone 18, iOS 27.2", Self.elements), ("Plan C · iPhone 18, iOS 27.2", Self.elements), ("Plan D · iPhone 18, iOS 27.2", other)]
        #expect(Look.elements(of: runs) == [
            Self.elements,
            ["on screen: the same as under Plan A · iPhone 18, iOS 27.2"],
            ["on screen: the same as under Plan A · iPhone 18, iOS 27.2"],
            other,
        ])
    }

    /// A run whose elements aren't listed, as one that attached nothing, is no run another's can be the same as.
    @Test func aRunWhoseElementsArentListedIsNoneToBeTheSameAs() {
        let runs: [(String, [String]?)] = [("Plan A · iPhone 18, iOS 27.2", nil), ("Plan B · iPhone 18, iOS 27.2", Self.elements), ("Plan C · iPhone 18, iOS 27.2", Self.elements)]
        #expect(Look.elements(of: runs) == [nil, Self.elements, ["on screen: the same as under Plan B · iPhone 18, iOS 27.2"]])
    }

    /// A screen past the elements listed ends with how many more there are and where its own hierarchy is: two runs
    /// whose elements are the same say so though each names its own file.
    @Test func elementsTheSameButForWhereTheRestAreAreSaidOnce() {
        let more = { (path: String) in Self.elements + ["  and 12 more in \(path)"] }
        let runs: [(String, [String]?)] = [("Plan A · iPhone 18, iOS 27.2", more("/images/run/A.txt")), ("Plan B · iPhone 18, iOS 27.2", more("/images/run/B.txt"))]
        #expect(Look.elements(of: runs) == [more("/images/run/A.txt"), ["on screen: the same as under Plan A · iPhone 18, iOS 27.2"]])
    }

    /// The line on a system alert is said under the run whose screenshot shows it, and isn't part of the elements: a
    /// configuration with a screenshot and those without, on the same screen, list the elements once, as a field report
    /// of a UI test under three configurations found they didn't.
    @Test func theSystemAlertLineIsNoPartOfTheElements() {
        let missing = [#"on screen, nothing the query's "checkout" Button matches:"#, #"  Application "App""#, #"    Button "Continue", identifier "continue""#]
        let alerted = [Look.appsOnly] + missing
        let runs: [(String, [String]?)] = [("Plan A · iPhone 18, iOS 27.2", alerted), ("Plan B · iPhone 18, iOS 27.2", missing), ("Plan C · iPhone 18, iOS 27.2", missing)]
        #expect(Look.elements(of: runs) == [
            alerted,
            ["on screen: the same as under Plan A · iPhone 18, iOS 27.2"],
            ["on screen: the same as under Plan A · iPhone 18, iOS 27.2"],
        ])
        let later: [(String, [String]?)] = [("Plan A · iPhone 18, iOS 27.2", missing), ("Plan B · iPhone 18, iOS 27.2", alerted)]
        #expect(Look.elements(of: later) == [missing, [Look.appsOnly, "on screen: the same as under Plan A · iPhone 18, iOS 27.2"]])
    }

    /// A run that kept no hierarchy lists no element, so it says so under each run rather than "the same as" another.
    @Test func noHierarchyKeptIsSaidUnderEachRun() {
        let none = ["on screen: no hierarchy kept; XCTest attaches one when a query fails"]
        let runs: [(String, [String]?)] = [("Plan A · iPhone 18, iOS 27.2", none), ("Plan B · iPhone 18, iOS 27.2", none)]
        #expect(Look.elements(of: runs) == [none, none])
    }

    static func hierarchy() throws -> FailureHierarchy {
        FailureHierarchy(content: .read(try #require(UIHierarchy(text: UIHierarchyTests.captured))), path: "hierarchy.txt")
    }
    static let appsOnly = "the elements below are the app's only; a system alert, as a permission request, shows only in the screenshot"

    /// A query that found nothing, with a screenshot kept: a system alert covering the app is another process's, so the
    /// list can't show it and the screenshot can.
    @Test func aQueryThatFoundNothingBesideAScreenshotSaysTheListIsTheAppsOnly() throws {
        let lines = Look.hierarchyLines(try Self.hierarchy(), query: UIQuery(text: "checkout", type: "Button"), screenshot: true)
        #expect(lines.prefix(2) == [Self.appsOnly, #"on screen, nothing the query's "checkout" Button matches:"#])
    }

    /// With no screenshot to look at, or a query that found its element, there's nothing to say.
    @Test func noScreenshotOrAFoundQueryAddsNothing() throws {
        #expect(!Look.hierarchyLines(try Self.hierarchy(), query: UIQuery(text: "checkout", type: "Button"), screenshot: false).contains(Self.appsOnly))
        #expect(!Look.hierarchyLines(try Self.hierarchy(), query: UIQuery(text: "continue", type: "Button"), screenshot: true).contains(Self.appsOnly))
    }

    /// Every failed test is looked at for a screen recording, however many failed: with none recorded, look says no
    /// failed test kept one, not that none of the first few did.
    @Test func everyFailedTestIsLookedAtForARecording() async {
        let bundle = "/runs/test_sim_1.xcresult"
        let nodes = (1...41).map { #"{"nodeType":"Test Case","nodeIdentifier":"Suite/test_\#($0)()","name":"test_\#($0)()","result":"Failed"}"# }.joined(separator: ",")
        let runner = FakeRunner(responses: ["xcrun xcresulttool get test-results tests --path \(bundle) --compact": .init(status: 0, stdout: #"{"testNodes":[\#(nodes)]}"#)])
        let text = await Look.report(bundle: ResultBundle(path: bundle, runner: runner), named: nil, keptIn: FileManager.default.temporaryDirectory.appending(path: "xcrew-look-\(UUID().uuidString)"), now: Date())
        #expect(text == "xcrew: no failed test in test_sim_1.xcresult kept a screen recording, as a UI test's failed run does; `xcrew look <Suite/test> --bundle /runs/test_sim_1.xcresult` shows one test's steps", "\(text)")
    }

    /// `look` takes the name the run's text gives a test: a nested suite's, `Inner/fails()`, means the one nested id that
    /// ends with it, and a crash's filed under `System Failures` means the `xctest (<pid>)` case its message names.
    @Test func lookTakesTheTextsNameForANestedTestOrACrashCase() {
        let listing = TestList(#"{"testNodes":[{"nodeType":"Test Case","name":"fails()","nodeIdentifier":"Outer/Inner/fails()","result":"Failed"},{"nodeType":"Test Suite","name":"System Failures","children":[{"nodeType":"Test Case","name":"xctest (1) encountered an error","nodeIdentifier":"xctest (1) encountered an error","result":"Failed","children":[{"nodeType":"Failure Message","name":"Crash: xctest at Suite.crashes()"}]}]}]}"#)
        let lookup = TestLookup(nodes: listing.nodes)
        #expect(Look.test("Inner/fails()", among: lookup) == TestID(xcresultID: "Outer/Inner/fails()"))
        #expect(Look.test("Suite/crashes()", among: lookup) == TestID(xcresultID: "xctest (1) encountered an error"))
        // As MobileBuildMCP's Discovered list names them, from the target.
        #expect(Look.test("NestedTests/Inner/fails", among: lookup) == TestID(xcresultID: "Outer/Inner/fails()"))
        #expect(Look.test("Target/Suite/crashes()", among: lookup) == TestID(xcresultID: "xctest (1) encountered an error"))
    }

    /// `look` takes a nested suite's test as the bundle names it, so its suite's `/` isn't read as a target's.
    @Test func lookTakesANestedSuitesTestAsTheBundleNamesIt() {
        #expect(TestID(suite: "Suite", name: "test").lookName == "Suite/test")
        #expect(TestID(xcresultID: "Outer/Inner/fails()").lookName == "Outer/Inner/fails()")
        #expect(TestID(xcresultID: "Suite/sizes(value:)").lookName == "Suite/sizes(value:)")
    }

    /// A name the bundle doesn't list that ends as a test's id does, with `()` or with its arguments' labels, is taken as
    /// the bundle's own, its first part kept.
    @Test func aNameEndingAsAnIDIsTheBundlesOwnWhenItsNotListed() {
        #expect(Look.test("Outer/Inner/sizes(value:)", among: TestLookup(cases: [:])) == TestID(xcresultID: "Outer/Inner/sizes(value:)"))
    }

    /// A top-level test is found by its function's name, `()` or not, as any test is.
    @Test func aTopLevelTestIsFoundWithOrWithoutItsParentheses() {
        let lookup = TestLookup(cases: [TestID(xcresultID: "seededFailure()"): []])
        #expect(Look.test("seededFailure()", among: lookup) == TestID(xcresultID: "seededFailure()"))
        #expect(Look.test("seededFailure", among: lookup) == TestID(xcresultID: "seededFailure()"))
    }

    /// The name `look` suggests for a test, a nested suite's, one taking arguments and a crash's case, finds that test.
    @Test(arguments: ["Outer/Inner/fails()", "Suite/sizes(value:)", "xctest (1) encountered an error"])
    func theNameLookSuggestsFindsItsTest(id: String) {
        let test = TestID(xcresultID: id)
        #expect(Look.test(test.lookName, among: TestLookup(cases: [test: []])) == test)
    }

    /// The line naming the failed tests not shown names each as a `look` command on this bundle takes it, one shell word.
    @Test func theLineOnTestsNotShownNamesEachAsAShellWord() {
        let tests = [TestID(suite: "Suite", name: "test"), TestID(xcresultID: "Outer/Inner/fails()"), TestID(xcresultID: "xctest (1) encountered an error")]
        #expect(Look.moreLine(tests, bundle: "/runs/Run.xcresult") == "and 3 more failed tests: `xcrew look Suite/test --bundle /runs/Run.xcresult`, `xcrew look 'Outer/Inner/fails()' --bundle /runs/Run.xcresult` and `xcrew look 'xctest (1) encountered an error' --bundle /runs/Run.xcresult`")
    }

    /// A crash's case is headed by its own name, as `look` takes it, with no `/` after it.
    @Test func aCrashsCaseIsHeadedByItsName() async {
        let text = await Look.report(bundle: ResultBundle(path: "/runs/Run.xcresult", runner: FakeRunner()), test: TestID(xcresultID: "xctest (1) encountered an error"), cases: [:], failed: [], keptIn: FileManager.default.temporaryDirectory.appending(path: "xcrew-look-\(UUID().uuidString)"), now: Date())
        #expect(text.hasPrefix("xcrew: couldn't read xctest (1) encountered an error's steps in Run.xcresult;"), "\(text)")
    }

    /// The line on a test list that couldn't be read names its xcresulttool command with the bundle quoted for a shell.
    @Test func theLineOnTestsNotReadQuotesItsPath() async {
        let text = await Look.report(bundle: ResultBundle(path: "/My Runs/Run.xcresult", runner: FakeRunner()), named: nil, keptIn: FileManager.default.temporaryDirectory.appending(path: "xcrew-look-\(UUID().uuidString)"), now: Date())
        #expect(text == "xcrew: couldn't read the tests in Run.xcresult; `xcrun xcresulttool get test-results tests --path '/My Runs/Run.xcresult'` says why", "\(text)")
    }

    /// The line on a test whose steps couldn't be read names its xcresulttool command with each word quoted for a shell.
    @Test func theLineOnStepsNotReadQuotesItsCommand() async {
        let text = await Look.report(bundle: ResultBundle(path: "/My Runs/Run.xcresult", runner: FakeRunner()), test: TestID(xcresultID: "Outer/Inner/fails()"), cases: [:], failed: [], keptIn: FileManager.default.temporaryDirectory.appending(path: "xcrew-look-\(UUID().uuidString)"), now: Date())
        #expect(text.hasSuffix("`xcrun xcresulttool get test-results activities --test-id 'Outer/Inner/fails()' --path '/My Runs/Run.xcresult'` says why"), "\(text)")
    }
}
