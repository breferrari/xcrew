import Testing
@testable import XcrewCore

@Suite struct TestIDTests {
    @Test(arguments: ["Suite/test", "Suite/test()"])
    func withOrWithoutParenthesesItIsTheSameTest(spelling: String) {
        #expect(TestID(xcresultID: spelling) == TestID(suite: "Suite", name: "test"))
    }

    @Test func itShowsWithoutParenthesesAndAsksXcresulttoolWithThem() {
        let test = TestID(suite: "PaymentsTests", name: "test_refund()")
        #expect(test.shown == "PaymentsTests/test_refund")
        #expect(test.xcresultID == "PaymentsTests/test_refund()")
    }

    @Test func anIdentifierWithoutASlashIsKeptWhole() {
        #expect(TestID(xcresultID: "Plain").shown == "Plain/")
        #expect(TestID(xcresultID: "Suite/Nested/test()") == TestID(suite: "Suite", name: "Nested/test"))
    }

    /// A test's own id beats a nested suite's test whose id ends with it.
    @Test func itsOwnIDBeatsANestedOne() {
        let ids: Set = [TestID(suite: "Inner", name: "passes"), TestID(xcresultID: "Outer/Inner/passes()")]
        #expect(TestLookup(ids: ids).resolution(of: TestID(suite: "Inner", name: "passes")) == .found(TestID(suite: "Inner", name: "passes")))
    }

    /// A test the text names from its own suite is the one nested id that ends with it.
    @Test func theOneNestedIDEndingWithItIsIts() {
        let ids: Set = [TestID(xcresultID: "Outer/Inner/fails()"), TestID(suite: "Inner", name: "passes")]
        #expect(TestLookup(ids: ids).resolution(of: TestID(suite: "Inner", name: "fails")) == .found(TestID(xcresultID: "Outer/Inner/fails()")))
    }

    /// Two nested ids ending with it take no guess, and no id at all is missing.
    @Test func twoNestedIDsEndingWithItAreAmbiguous() {
        let ids: Set = [TestID(xcresultID: "A/Inner/fails()"), TestID(xcresultID: "B/Inner/fails()")]
        #expect(TestLookup(ids: ids).resolution(of: TestID(suite: "Inner", name: "fails")) == .ambiguous([TestID(xcresultID: "A/Inner/fails()"), TestID(xcresultID: "B/Inner/fails()")]))
        #expect(TestLookup(ids: ids).resolution(of: TestID(suite: "Inner", name: "gone")) == .missing)
    }

    /// An id with no `/`, as the case a crash under `System Failures` is filed as, asks xcresulttool by itself.
    @Test func anIDWithoutASlashAsksXcresulttoolByItself() {
        #expect(TestID(xcresultID: "xctest (80341) encountered an error").xcresultID == "xctest (80341) encountered an error")
    }

    /// A test that takes arguments is listed with them in its id, `ShapesTests/parameterised(value:)` in the test bed's
    /// shapes captures, so it's asked for as listed, and its added line names it so.
    @Test func aTestWithArgumentsIsAskedForAsTheBundleListsIt() {
        let test = TestID(xcresultID: "ShapesTests/parameterised(value:)")
        #expect(test.xcresultID == "ShapesTests/parameterised(value:)")
        let text = MobileText("\n🧪 Test\n\n❌ 1 test failed, 0 passed, 0 skipped (⏱️ 1.0s)")
        #expect(text.adding(unlisted: [(test, "it failed", nil)])?.text.contains("  ✗ ShapesTests / parameterised(value:): it failed\n") == true)
    }

    /// A test the text names is the bundle's own id, else the one nested id ending with it, else the `System Failures`
    /// case its crash is filed under: one rule for every lookup.
    @Test func aTestIsItsOwnIDTheOneNestedIDOrItsCrashCase() {
        let listing = TestList(#"{"testNodes":[{"nodeType":"Test Case","name":"fails()","nodeIdentifier":"Outer/Inner/fails()","result":"Failed"},{"nodeType":"Test Case","name":"xctest (1) encountered an error","nodeIdentifier":"xctest (1) encountered an error","result":"Failed","children":[{"nodeType":"Failure Message","name":"Crash: xctest at Suite.crashes()"}]}]}"#)
        let lookup = TestLookup(nodes: listing.nodes)
        #expect(lookup.resolution(of: TestID(suite: "Inner", name: "fails")) == .found(TestID(xcresultID: "Outer/Inner/fails()")))
        #expect(lookup.resolution(of: TestID(suite: "Suite", name: "crashes")) == .found(TestID(xcresultID: "xctest (1) encountered an error")))
        #expect(lookup.resolution(of: TestID(suite: "Suite", name: "gone")) == .missing)
    }

    /// The line on a test several nested ids end with names five at most, and counts the rest.
    @Test func theLineOnATestSeveralIDsEndWithNamesFiveAtMost() {
        let ids = (1...7).map { TestID(xcresultID: "Module\($0)/Loading/showsSpinner()") }
        #expect(FailureNotes.severalByThatName(ids) == "the result bundle has more than one test by that name: Module1/Loading/showsSpinner, Module2/Loading/showsSpinner, Module3/Loading/showsSpinner, Module4/Loading/showsSpinner, Module5/Loading/showsSpinner and 2 more (in the result bundle's test list)")
    }
}
