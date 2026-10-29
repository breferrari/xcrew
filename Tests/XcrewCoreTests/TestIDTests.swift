import Testing
@testable import XcrewCore

@Suite struct TestIDTests {
    @Test(arguments: ["Suite/test", "Suite/test()", "Suite / test()", "Suite / test"])
    func everySpellingIsTheSameTest(spelling: String) {
        #expect(TestID(parsing: spelling) == TestID(suite: "Suite", name: "test"))
    }

    @Test func itShowsWithoutParenthesesAndAsksXcresulttoolWithThem() {
        let test = TestID(suite: "PaymentsTests", name: "test_refund()")
        #expect(test.shown == "PaymentsTests/test_refund")
        #expect(test.xcresultID == "PaymentsTests/test_refund()")
    }

    @Test func somethingThatIsNotATestIsNot() {
        #expect(TestID(parsing: "no slash here") == nil)
        #expect(TestID(parsing: "/test") == nil)
        #expect(TestID(parsing: "Suite/") == nil)
    }
}
