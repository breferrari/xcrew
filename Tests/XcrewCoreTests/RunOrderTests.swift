import Testing
@testable import XcrewCore

/// A failing run's failed tests from its result bundle, in the order its text lists them, with the text's message and
/// place where the bundle gives none; and the images the notes kept for each.
struct RunOrderTests {
    /// With the bundle's list, the text's failed tests only order the bundle's: a test only the text names, as a retry
    /// the bundle counts passed, is never listed. The text's other failures stay where they were.
    @Test func theTextOnlyOrdersTheBundlesFailedTests() {
        let bundled = [ToolOutput.Failure(title: "Suite/test", message: "from the bundle", isTest: true)]
        let text = [
            ToolOutput.Failure(title: "Suite/retried", message: "from the text", isTest: true),
            ToolOutput.Failure(title: "App.swift:3", message: "a warning as an error", isTest: false),
        ]
        #expect(Report.inRunOrder(bundled, text: text, cleared: [TestID(suite: "Suite", name: "retried")]).failures.map(\.title) == ["App.swift:3", "Suite/test"])
    }

    /// A test only the text lists that the bundle has no entry for stays a failure in its place, with the text's
    /// message and place, and is returned as disagreeing.
    @Test func anUnlistedTestStaysAFailureWithTheTextsMessage() {
        let bundled = [ToolOutput.Failure(title: "Suite/test", message: "from the bundle", isTest: true)]
        let text = [
            ToolOutput.Failure(title: "Suite/gone", message: "from the text", where: "Gone.swift:2", isTest: true),
            ToolOutput.Failure(title: "Suite/test", message: "the text's", isTest: true),
        ]
        let ordered = Report.inRunOrder(bundled, text: text, cleared: [])
        #expect(ordered.failures.map { "\($0.title) | \($0.message) | \($0.where ?? "-")" } == ["Suite/gone | from the text | Gone.swift:2", "Suite/test | from the bundle | -"])
        #expect(ordered.disagreeing == [TestID(suite: "Suite", name: "gone")])
    }

    /// A test in a nested suite, which the bundle names from its outermost suite and the text from its own, takes its
    /// place in the run's order under the bundle's name, the one the bundle's passed tests give the ledger.
    @Test func aNestedSuitesTestTakesItsPlaceUnderTheBundlesName() {
        let bundled = [
            ToolOutput.Failure(title: "Later/test", message: "second", isTest: true),
            ToolOutput.Failure(title: "Outer/Inner/test", message: "first", where: "Inner.swift:7", isTest: true, target: "FeatureTests"),
        ]
        let text = [
            ToolOutput.Failure(title: "Inner/test", message: "the text's first", isTest: true),
            ToolOutput.Failure(title: "Later/test", message: "the text's second", isTest: true),
        ]
        #expect(Report.inRunOrder(bundled, text: text, cleared: []).failures.map { "\($0.title) | \($0.message) | \($0.where ?? "-") | \($0.target ?? "-")" } == [
            "Outer/Inner/test | first | Inner.swift:7 | FeatureTests",
            "Later/test | second | - | -",
        ])
    }

    /// A name the text gives that the ends of two of the bundle's share matches neither: both follow the run's order, as
    /// tests only the bundle lists, rather than one taking the other's place.
    @Test func aNameTwoNestedSuitesShareMatchesNeither() {
        let bundled = ["Later/test", "A/Inner/test", "B/Inner/test"].map { ToolOutput.Failure(title: $0, message: $0, isTest: true) }
        let text = ["Inner/test", "Later/test"].map { ToolOutput.Failure(title: $0, message: "", isTest: true) }
        #expect(Report.inRunOrder(bundled, text: text, cleared: []).failures.map(\.title) == ["Later/test", "A/Inner/test", "B/Inner/test"])
        #expect(Report.inRunOrder(bundled, text: text, cleared: []).disagreeing.isEmpty)
    }

    /// A nested suite's test the text lists twice is matched once and never disagrees: the bundle lists it as failed.
    @Test func aNestedSuitesTestListedTwiceNeverDisagrees() {
        let bundled = [ToolOutput.Failure(title: "Outer/Inner/test", message: "", isTest: true)]
        let text = ["Inner/test", "Inner/test"].map { ToolOutput.Failure(title: $0, message: "", isTest: true) }
        #expect(Report.inRunOrder(bundled, text: text, cleared: []).disagreeing.isEmpty)
    }

    /// The note reads a disagreeing test by the name the text gives: one the bundle files only in a nested suite, under a
    /// longer name, it doesn't list under that name.
    @Test func theNoteReadsADisagreeingTestByTheTextsName() {
        let listing = TestList(#"{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"Outer/Inner/testFlaky()","result":"Passed"}]}"#)
        #expect(Report.notFailedInBundleNote([TestID(suite: "Inner", name: "testFlaky")], results: ResultBundle.results(in: listing.nodes))
            == "xcrew: MobileBuildMCP's result lists as failed a test its result bundle doesn't list among its failures under that name: Inner/testFlaky, which the bundle has no entry for under that name. A test the bundle doesn't count as passed, skipped or an expected failure stays in the failures here, as MobileBuildMCP gives it.")
    }

    /// The note names several disagreeing tests, each with what the bundle records under its name.
    @Test func theNoteNamesSeveralDisagreeingTestsEachWithItsResult() {
        let listing = TestList(#"{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"Suite/skipped()","result":"Skipped"},{"nodeType":"Test Case","nodeIdentifier":"Suite/expected()","result":"Expected Failure"}]}"#)
        #expect(Report.notFailedInBundleNote(["skipped", "expected"].map { TestID(suite: "Suite", name: $0) }, results: ResultBundle.results(in: listing.nodes))
            == "xcrew: MobileBuildMCP's result lists as failed tests its result bundle doesn't list among its failures under that name: Suite/skipped, which the bundle counts as skipped; Suite/expected, which the bundle counts as an expected failure. A test the bundle counts as passed, skipped or an expected failure is left out of the failures here.")
    }

    /// A disagreeing test the bundle records neither passed, skipped nor an expected failure, as `unknown` for one its
    /// process was killed under, stays a failure, and the note says what the bundle records.
    @Test func theNoteKeepsATestTheBundleRecordsNeitherPassedSkippedNorExpected() {
        let listing = TestList(#"{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"Suite/killed()","result":"unknown"}]}"#)
        #expect(Report.notFailedInBundleNote([TestID(suite: "Suite", name: "killed")], results: ResultBundle.results(in: listing.nodes))
            == "xcrew: MobileBuildMCP's result lists as failed a test its result bundle doesn't list among its failures under that name: Suite/killed, which the bundle records as unknown. A test the bundle doesn't count as passed, skipped or an expected failure stays in the failures here, as MobileBuildMCP gives it.")
        #expect(ResultBundle.cleared(in: ResultBundle.results(in: listing.nodes)).isEmpty)
    }

    /// A test the bundle records both passed and `unknown` is none of the run's passed tests either: the report never
    /// lists one test as both failed and passed.
    @Test func aTestRecordedPassedAndUnknownIsNotPassed() {
        let listing = TestList(#"{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"ModelTests/testDecode()","result":"Passed"},{"nodeType":"Test Case","nodeIdentifier":"ModelTests/testDecode()","result":"unknown"}]}"#)
        #expect(ResultBundle.passedTests(listing: listing).isEmpty)
    }

    /// A test the bundle records both passed and `unknown`, as one name in two test bundles where one's run was killed,
    /// isn't cleared: a pass in one is no sign the other passed.
    @Test func aTestRecordedPassedAndUnknownIsNotCleared() {
        let listing = TestList(#"{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"ModelTests/testDecode()","result":"Passed"},{"nodeType":"Test Case","nodeIdentifier":"ModelTests/testDecode()","result":"unknown"}]}"#)
        let results = ResultBundle.results(in: listing.nodes)
        #expect(ResultBundle.cleared(in: results).isEmpty)
        #expect(Report.notFailedInBundleNote([TestID(suite: "ModelTests", name: "testDecode")], results: results)
            == "xcrew: MobileBuildMCP's result lists as failed a test its result bundle doesn't list among its failures under that name: ModelTests/testDecode, which the bundle records as passed and unknown. A test the bundle doesn't count as passed, skipped or an expected failure stays in the failures here, as MobileBuildMCP gives it.")
    }

    /// A test one of whose entries records no result isn't cleared, nor passed, though another passed: no result is no
    /// sign it passed.
    @Test func aTestWithAnEntryRecordingNoResultIsNeitherClearedNorPassed() {
        let listing = TestList(#"{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"Suite/test()","result":"Passed"},{"nodeType":"Test Case","nodeIdentifier":"Suite/test()"}]}"#)
        #expect(ResultBundle.cleared(in: ResultBundle.results(in: listing.nodes)).isEmpty)
        #expect(ResultBundle.passedTests(listing: listing).isEmpty)
        #expect(Report.notFailedInBundleNote([TestID(suite: "Suite", name: "test")], results: ResultBundle.results(in: listing.nodes))
            == "xcrew: MobileBuildMCP's result lists as failed a test its result bundle doesn't list among its failures under that name: Suite/test, which the bundle records as passed and with no result. A test the bundle doesn't count as passed, skipped or an expected failure stays in the failures here, as MobileBuildMCP gives it.")
    }

    /// A kept test's results read as the note words them elsewhere: an expected failure with its article.
    @Test func aKeptTestsExpectedFailureReadsAsTheNoteWordsIt() {
        let listing = TestList(#"{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"Suite/test()","result":"Expected Failure"},{"nodeType":"Test Case","nodeIdentifier":"Suite/test()","result":"unknown"}]}"#)
        #expect(Report.notFailedInBundleNote([TestID(suite: "Suite", name: "test")], results: ResultBundle.results(in: listing.nodes))
            == "xcrew: MobileBuildMCP's result lists as failed a test its result bundle doesn't list among its failures under that name: Suite/test, which the bundle records as an expected failure and unknown. A test the bundle doesn't count as passed, skipped or an expected failure stays in the failures here, as MobileBuildMCP gives it.")
    }

    /// A test whose test plan configurations disagree, one passed and one `unknown` under a case recorded passed, is
    /// neither cleared nor passed: each configuration's result counts.
    @Test func aTestWhoseConfigurationsDisagreeIsNeitherClearedNorPassed() {
        let listing = TestList(#"{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"Suite/test()","result":"Passed","children":[{"nodeType":"Test Plan Configuration","name":"First","nodeIdentifier":"1","result":"Passed"},{"nodeType":"Test Plan Configuration","name":"Second","nodeIdentifier":"2","result":"unknown"}]}]}"#)
        #expect(ResultBundle.cleared(in: ResultBundle.results(in: listing.nodes)).isEmpty)
        #expect(ResultBundle.passedTests(listing: listing).isEmpty)
    }

    /// A test the bundle lists as failed through a crash it files under `System Failures` isn't passed, though its own
    /// case records it passed: the report never lists one test as both failed and passed.
    @Test func aTestACrashUnderSystemFailuresNamesIsNotPassed() {
        let listing = TestList(#"{"testNodes":[{"nodeType":"Test Case","name":"test()","nodeIdentifier":"Suite/test()","result":"Passed"},{"nodeType":"Test Suite","name":"System Failures","children":[{"nodeType":"Test Case","name":"xctest (1) encountered an error","nodeIdentifier":"xctest (1) encountered an error","result":"Failed","children":[{"nodeType":"Failure Message","name":"Crash: xctest at Suite.test()"}]}]}]}"#)
        #expect(ResultBundle.failedTests(listing: listing)?.map(\.title) == ["Suite/test"])
        #expect(ResultBundle.passedTests(listing: listing).isEmpty)
    }

    /// A kept test with three results or more lists them as a list, not a chain of ands.
    @Test func aKeptTestsResultsReadAsAList() {
        let listing = TestList(#"{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"Suite/test()","result":"Passed"},{"nodeType":"Test Case","nodeIdentifier":"Suite/test()","result":"Expected Failure"},{"nodeType":"Test Case","nodeIdentifier":"Suite/test()","result":"unknown"},{"nodeType":"Test Case","nodeIdentifier":"Suite/test()"}]}"#)
        #expect(Report.notFailedInBundleNote([TestID(suite: "Suite", name: "test")], results: ResultBundle.results(in: listing.nodes))
            == "xcrew: MobileBuildMCP's result lists as failed a test its result bundle doesn't list among its failures under that name: Suite/test, which the bundle records as an expected failure, passed and unknown, and with no result. A test the bundle doesn't count as passed, skipped or an expected failure stays in the failures here, as MobileBuildMCP gives it.")
    }

    /// A disagreeing test the bundle files more than once, as in two test bundles, skipped in one and passed in the
    /// other, counts as passed.
    @Test func theNoteCountsATestSkippedInOneEntryAndPassedInAnotherAsPassed() {
        let listing = TestList(#"{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"Suite/test()","result":"Skipped"},{"nodeType":"Test Case","nodeIdentifier":"Suite/test()","result":"Passed"}]}"#)
        #expect(Report.notFailedInBundleNote([TestID(suite: "Suite", name: "test")], results: ResultBundle.results(in: listing.nodes))
            == "xcrew: MobileBuildMCP's result lists as failed a test its result bundle doesn't list among its failures under that name: Suite/test, which the bundle counts as passed. A test the bundle counts as passed, skipped or an expected failure is left out of the failures here.")
    }

    /// A name the text lists twice, as a parallel run's clones may, is its own test's both times: never a nested suite's
    /// test whose name ends with it.
    @Test func aNameListedTwiceIsItsOwnTestsBothTimes() {
        let bundled = ["Later/test", "Inner/test", "A/Inner/test"].map { ToolOutput.Failure(title: $0, message: $0, isTest: true) }
        let text = ["Inner/test", "Inner/test", "Later/test"].map { ToolOutput.Failure(title: $0, message: "", isTest: true) }
        #expect(Report.inRunOrder(bundled, text: text, cleared: []).failures.map(\.title) == ["Inner/test", "Later/test", "A/Inner/test"])
    }

    /// A test only the text lists, listed twice as a parallel run's clones may, disagrees once, and stays a failure
    /// once when the bundle has no entry for it.
    @Test func aTestOnlyTheTextListsTwiceDisagreesOnce() {
        let text = ["Suite/flaky", "Suite/flaky"].map { ToolOutput.Failure(title: $0, message: "", isTest: true) }
        let flaky = TestID(suite: "Suite", name: "flaky")
        #expect(Report.inRunOrder([], text: text, cleared: [flaky]).disagreeing == [flaky])
        #expect(Report.inRunOrder([], text: text, cleared: [flaky]).failures.isEmpty)
        #expect(Report.inRunOrder([], text: text, cleared: []).failures.map(\.title) == ["Suite/flaky"])
    }

    /// A nested suite's failed test has no images kept under the end of its name: those are a test of that name's own,
    /// as the notes look a test's up under the name the text gives it.
    @Test func aNestedSuitesTestHasNoImagesOfATestNamedAsItsEnd() {
        let images = [TestID(suite: "Inner", name: "test"): FailureImages(paths: ["/run/Inner/test/screen.png"], folder: "/run/Inner/test")]
        let failures = ["Inner/test", "Outer/Inner/test"].map { ToolOutput.Failure(title: $0, message: "", isTest: true) }
        #expect(Report.attaching(images, to: failures).map(\.images) == [["/run/Inner/test/screen.png"], nil])
    }

    /// A failed test the bundle gives no message keeps the text's, as it keeps its place when the bundle gives none.
    @Test func aFailedTestTheBundleGivesNoMessageKeepsTheTexts() {
        let bundled = [ToolOutput.Failure(title: "Suite/test", message: "", isTest: true)]
        let text = [ToolOutput.Failure(title: "Suite/test", message: "the text's message", where: "Suite.swift:4", isTest: true)]
        #expect(Report.inRunOrder(bundled, text: text, cleared: []).failures.map { "\($0.message) | \($0.where ?? "-")" } == ["the text's message | Suite.swift:4"])
    }
}
