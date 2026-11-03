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
}
