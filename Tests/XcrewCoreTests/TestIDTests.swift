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

    /// An id with no `/` is a crash's case, kept whole as the suite, or a top-level Swift Testing test, with no suite.
    @Test func anIdentifierWithoutASlashIsACrashsCaseOrATestWithNoSuite() {
        #expect(TestID(xcresultID: "xctest (80341) encountered an error").shown == "xctest (80341) encountered an error/")
        #expect(TestID(xcresultID: "seededFailure()") == TestID(suite: "", name: "seededFailure"))
        #expect(TestID(xcresultID: "seededFailure()").shown == "seededFailure()")
        #expect(TestID(xcresultID: TestID(xcresultID: "seededFailure()").shown) == TestID(xcresultID: "seededFailure()"))
        #expect(TestID(xcresultID: "AppUITests-Runner (4242) encountered an error").xcresultID == "AppUITests-Runner (4242) encountered an error")
        #expect(TestID(xcresultID: "Suite/Nested/test()") == TestID(suite: "Suite", name: "Nested/test"))
    }

    /// An id with no `/`, as the case a crash under `System Failures` is filed as, asks xcresulttool by itself.
    @Test func anIDWithoutASlashAsksXcresulttoolByItself() {
        #expect(TestID(xcresultID: "xctest (80341) encountered an error").xcresultID == "xctest (80341) encountered an error")
    }

    /// A test that takes arguments is listed with them in its id, `ShapesTests/parameterised(value:)` in the test bed's
    /// shapes captures, so it's asked for as listed.
    @Test func aTestWithArgumentsIsAskedForAsTheBundleListsIt() {
        #expect(TestID(xcresultID: "ShapesTests/parameterised(value:)").xcresultID == "ShapesTests/parameterised(value:)")
    }

    /// The line on a test several nested ids end with names five at most, and counts the rest.
    @Test func theLineOnATestSeveralIDsEndWithNamesFiveAtMost() {
        let ids = (1...7).map { TestID(xcresultID: "Module\($0)/Loading/showsSpinner()") }
        #expect(FailureNotes.severalByThatName(ids) == "the result bundle has more than one test by that name: Module1/Loading/showsSpinner, Module2/Loading/showsSpinner, Module3/Loading/showsSpinner, Module4/Loading/showsSpinner, Module5/Loading/showsSpinner and 2 more (in the result bundle's test list)")
    }

    /// A line added for a top-level test names it from `(Unknown Suite)`, as MobileBuildMCP names one.
    @Test func aLineAddedForATestWithNoSuiteNamesItFromTheUnknownSuite() {
        let text = MobileText("\n🧪 Test\n\n❌ 1 test failed, 0 passed, 0 skipped (⏱️ 1.0s)")
        let added = text.adding(unlisted: [(test: TestID(xcresultID: "seededFailure()"), message: "it failed", place: nil)])
        #expect(added?.text.contains("  ✗ (Unknown Suite) / seededFailure(): it failed\n") == true, "\(added?.text ?? "")")
    }
}
