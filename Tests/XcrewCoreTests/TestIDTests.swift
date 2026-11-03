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

    /// The line on a test several nested ids end with names five at most, and counts the rest.
    @Test func theLineOnATestSeveralIDsEndWithNamesFiveAtMost() {
        let ids = (1...7).map { TestID(xcresultID: "Module\($0)/Loading/showsSpinner()") }
        #expect(FailureNotes.severalByThatName(ids) == "the result bundle has more than one test by that name: Module1/Loading/showsSpinner, Module2/Loading/showsSpinner, Module3/Loading/showsSpinner, Module4/Loading/showsSpinner, Module5/Loading/showsSpinner and 2 more (in the result bundle's test list)")
    }
}
