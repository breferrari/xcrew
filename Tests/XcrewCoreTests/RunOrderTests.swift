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
        #expect(Report.inRunOrder(bundled, text: text).failures.map(\.title) == ["App.swift:3", "Suite/test"])
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
        #expect(Report.inRunOrder(bundled, text: text).failures.map { "\($0.title) | \($0.message) | \($0.where ?? "-") | \($0.target ?? "-")" } == [
            "Outer/Inner/test | first | Inner.swift:7 | FeatureTests",
            "Later/test | second | - | -",
        ])
    }

    /// A name the text gives that the ends of two of the bundle's share matches neither: both follow the run's order, as
    /// tests only the bundle lists, rather than one taking the other's place.
    @Test func aNameTwoNestedSuitesShareMatchesNeither() {
        let bundled = ["Later/test", "A/Inner/test", "B/Inner/test"].map { ToolOutput.Failure(title: $0, message: $0, isTest: true) }
        let text = ["Inner/test", "Later/test"].map { ToolOutput.Failure(title: $0, message: "", isTest: true) }
        #expect(Report.inRunOrder(bundled, text: text).failures.map(\.title) == ["Later/test", "A/Inner/test", "B/Inner/test"])
        #expect(Report.inRunOrder(bundled, text: text).dropped.isEmpty)
    }

    /// A nested suite's test the text lists twice is matched once and never dropped: the bundle lists it as failed.
    @Test func aNestedSuitesTestListedTwiceIsNotDropped() {
        let bundled = [ToolOutput.Failure(title: "Outer/Inner/test", message: "", isTest: true)]
        let text = ["Inner/test", "Inner/test"].map { ToolOutput.Failure(title: $0, message: "", isTest: true) }
        #expect(Report.inRunOrder(bundled, text: text).dropped.isEmpty)
    }

    /// The note names a dropped nested suite's test with what the bundle records for it under its full name, and leaves
    /// out a test the bundle records as failed under the name the text gives.
    @Test func theNoteReadsANestedSuitesTestByItsFullNameAndLeavesOutAFailedOne() {
        let listing = TestList(#"{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"Outer/Inner/testFlaky()","result":"Passed"},{"nodeType":"Test Case","nodeIdentifier":"Suite/renamed()","result":"Failed"}]}"#)
        #expect(Report.notFailedInBundleNote([TestID(suite: "Inner", name: "testFlaky"), TestID(suite: "Suite", name: "renamed")], listing: listing)
            == "xcrew: MobileBuildMCP's text lists as failed a test its result bundle doesn't: Inner/testFlaky, which it counts as passed. The tests listed as failed here are the bundle's.")
    }

    /// A name the text lists twice, as a parallel run's clones may, is its own test's both times: never a nested suite's
    /// test whose name ends with it.
    @Test func aNameListedTwiceIsItsOwnTestsBothTimes() {
        let bundled = ["Later/test", "Inner/test", "A/Inner/test"].map { ToolOutput.Failure(title: $0, message: $0, isTest: true) }
        let text = ["Inner/test", "Inner/test", "Later/test"].map { ToolOutput.Failure(title: $0, message: "", isTest: true) }
        #expect(Report.inRunOrder(bundled, text: text).failures.map(\.title) == ["Inner/test", "Later/test", "A/Inner/test"])
    }

    /// A test only the text lists, listed twice as a parallel run's clones may, is dropped once.
    @Test func aTestOnlyTheTextListsTwiceIsDroppedOnce() {
        let text = ["Suite/flaky", "Suite/flaky"].map { ToolOutput.Failure(title: $0, message: "", isTest: true) }
        #expect(Report.inRunOrder([], text: text).dropped == [TestID(suite: "Suite", name: "flaky")])
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
        #expect(Report.inRunOrder(bundled, text: text).failures.map { "\($0.message) | \($0.where ?? "-")" } == ["the text's message | Suite.swift:4"])
    }
}
