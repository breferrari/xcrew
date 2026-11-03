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
        #expect(TestID(suite: "Inner", name: "passes").resolved(among: ids) == .found(TestID(suite: "Inner", name: "passes")))
    }

    /// A test the text names from its own suite is the one nested id that ends with it.
    @Test func theOneNestedIDEndingWithItIsIts() {
        let ids: Set = [TestID(xcresultID: "Outer/Inner/fails()"), TestID(suite: "Inner", name: "passes")]
        #expect(TestID(suite: "Inner", name: "fails").resolved(among: ids) == .found(TestID(xcresultID: "Outer/Inner/fails()")))
    }

    /// Two nested ids ending with it take no guess, and no id at all is missing.
    @Test func twoNestedIDsEndingWithItAreAmbiguous() {
        let ids: Set = [TestID(xcresultID: "A/Inner/fails()"), TestID(xcresultID: "B/Inner/fails()")]
        #expect(TestID(suite: "Inner", name: "fails").resolved(among: ids) == .ambiguous([TestID(xcresultID: "A/Inner/fails()"), TestID(xcresultID: "B/Inner/fails()")]))
        #expect(TestID(suite: "Inner", name: "gone").resolved(among: ids) == .missing)
    }

    /// An id with no `/`, as the case a crash under `System Failures` is filed as, asks xcresulttool by itself.
    @Test func anIDWithoutASlashAsksXcresulttoolByItself() {
        #expect(TestID(xcresultID: "xctest (80341) encountered an error").xcresultID == "xctest (80341) encountered an error")
    }

    /// A test the text names is the bundle's own id, else the one nested id ending with it, else the `System Failures`
    /// case its crash is filed under: one rule for every lookup.
    @Test func aTestIsItsOwnIDTheOneNestedIDOrItsCrashCase() {
        let listing = TestList(#"{"testNodes":[{"nodeType":"Test Case","name":"fails()","nodeIdentifier":"Outer/Inner/fails()","result":"Failed"},{"nodeType":"Test Case","name":"xctest (1) encountered an error","nodeIdentifier":"xctest (1) encountered an error","result":"Failed","children":[{"nodeType":"Failure Message","name":"Crash: xctest at Suite.crashes()"}]}]}"#)
        let cases = ResultBundle.testCases(in: listing.nodes)
        let (ids, crashes) = (Set(cases.keys), ResultBundle.crashCases(in: listing.nodes))
        #expect(ResultBundle.resolution(of: TestID(suite: "Inner", name: "fails"), among: ids, crashCases: crashes) == .found(TestID(xcresultID: "Outer/Inner/fails()")))
        #expect(ResultBundle.resolution(of: TestID(suite: "Suite", name: "crashes"), among: ids, crashCases: crashes) == .found(TestID(xcresultID: "xctest (1) encountered an error")))
        #expect(ResultBundle.resolution(of: TestID(suite: "Suite", name: "gone"), among: ids, crashCases: crashes) == .missing)
    }

    /// The line on a test several nested ids end with names five at most, and counts the rest.
    @Test func theLineOnATestSeveralIDsEndWithNamesFiveAtMost() {
        let ids = (1...7).map { TestID(xcresultID: "Module\($0)/Loading/showsSpinner()") }
        #expect(FailureNotes.severalByThatName(ids) == "the result bundle has more than one test by that name: Module1/Loading/showsSpinner, Module2/Loading/showsSpinner, Module3/Loading/showsSpinner, Module4/Loading/showsSpinner, Module5/Loading/showsSpinner and 2 more (in the result bundle's test list)")
    }
}
