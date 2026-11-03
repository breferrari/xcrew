import Testing
@testable import XcrewCore

@Suite struct TestLookupTests {
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

    /// A test the text names is the bundle's own id, else the one nested id ending with it, else the `System Failures`
    /// case its crash is filed under: one rule for every lookup.
    @Test func aTestIsItsOwnIDTheOneNestedIDOrItsCrashCase() {
        let listing = TestList(#"{"testNodes":[{"nodeType":"Test Case","name":"fails()","nodeIdentifier":"Outer/Inner/fails()","result":"Failed"},{"nodeType":"Test Case","name":"xctest (1) encountered an error","nodeIdentifier":"xctest (1) encountered an error","result":"Failed","children":[{"nodeType":"Failure Message","name":"Crash: xctest at Suite.crashes()"}]}]}"#)
        let lookup = TestLookup(nodes: listing.nodes)
        #expect(lookup.resolution(of: TestID(suite: "Inner", name: "fails")) == .found(TestID(xcresultID: "Outer/Inner/fails()")))
        #expect(lookup.resolution(of: TestID(suite: "Suite", name: "crashes")) == .found(TestID(xcresultID: "xctest (1) encountered an error")))
        #expect(lookup.resolution(of: TestID(suite: "Suite", name: "gone")) == .missing)
    }
}
