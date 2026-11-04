import Testing
@testable import XcrewCore

/// The one rule a test the run's text names is found among the result bundle's ids by.
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

    /// A Swift Testing test the text names by its display name is the bundle's test of that name: under its innermost
    /// suite, as `Inner / Adds numbers`, or under `(Unknown Suite)`, as MobileBuildMCP's log names it, and a top-level
    /// test's under `(Unknown Suite)` alone.
    @Test func aDisplayNameIsItsTestsUnderItsSuiteOrUnknownSuite() {
        let listing = TestList(#"{"testNodes":[{"nodeType":"Test Case","name":"Adds numbers","nodeIdentifier":"Outer/Inner/addsNumbers()","result":"Failed"},{"nodeType":"Test Case","name":"Top level","nodeIdentifier":"topLevel()","result":"Failed"},{"nodeType":"Test Case","name":"fails()","nodeIdentifier":"Outer/Inner/fails()","result":"Failed"}]}"#)
        let lookup = TestLookup(nodes: listing.nodes)
        #expect(lookup.resolution(of: TestID(suite: "Inner", name: "Adds numbers")) == .found(TestID(xcresultID: "Outer/Inner/addsNumbers()")))
        #expect(lookup.resolution(of: TestID(suite: "(Unknown Suite)", name: "Adds numbers")) == .found(TestID(xcresultID: "Outer/Inner/addsNumbers()")))
        #expect(lookup.resolution(of: TestID(suite: "(Unknown Suite)", name: "Top level")) == .found(TestID(xcresultID: "topLevel()")))
        #expect(lookup.resolution(of: TestID(suite: "Outer", name: "Adds numbers")) == .missing)
    }

    /// A display name two tests share takes no guess where both could be meant, and is its own suite's where only one is.
    @Test func aDisplayNameTwoTestsShareIsAmbiguous() {
        let listing = TestList(#"{"testNodes":[{"nodeType":"Test Case","name":"Adds numbers","nodeIdentifier":"Outer/Inner/addsNumbers()","result":"Failed"},{"nodeType":"Test Case","name":"Adds numbers","nodeIdentifier":"Other/adds()","result":"Failed"}]}"#)
        let lookup = TestLookup(nodes: listing.nodes)
        #expect(lookup.resolution(of: TestID(suite: "(Unknown Suite)", name: "Adds numbers")) == .ambiguous([TestID(xcresultID: "Other/adds()"), TestID(xcresultID: "Outer/Inner/addsNumbers()")]))
        #expect(lookup.resolution(of: TestID(suite: "Inner", name: "Adds numbers")) == .found(TestID(xcresultID: "Outer/Inner/addsNumbers()")))
        #expect(lookup.resolution(of: TestID(suite: "Other", name: "Adds numbers")) == .found(TestID(xcresultID: "Other/adds()")))
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
        let listing = TestList(#"{"testNodes":[{"nodeType":"Test Case","name":"fails()","nodeIdentifier":"Outer/Inner/fails()","result":"Failed"},{"nodeType":"Test Case","name":"xctest (1) encountered an error","nodeIdentifier":"xctest (1) encountered an error","result":"Failed","children":[{"nodeType":"Failure Message","name":"Crash: xctest at Suite.testCrashes()"}]}]}"#)
        let lookup = TestLookup(nodes: listing.nodes)
        #expect(lookup.resolution(of: TestID(suite: "Inner", name: "fails")) == .found(TestID(xcresultID: "Outer/Inner/fails()")))
        #expect(lookup.resolution(of: TestID(suite: "Suite", name: "testCrashes")) == .found(TestID(xcresultID: "xctest (1) encountered an error")))
        #expect(lookup.resolution(of: TestID(suite: "Suite", name: "gone")) == .missing)
    }

    /// A test in a suite nested deeper is the one id that ends with the name the text gives it from its own suite.
    @Test func aDeeperNestedIDEndingWithItIsIts() {
        let lookup = TestLookup(ids: [TestID(xcresultID: "A/B/Inner/fails()"), TestID(xcresultID: "A/Other/fails()")])
        #expect(lookup.resolution(of: TestID(suite: "Inner", name: "fails")) == .found(TestID(xcresultID: "A/B/Inner/fails()")))
        #expect(lookup.resolution(of: TestID(suite: "B", name: "Inner/fails")) == .found(TestID(xcresultID: "A/B/Inner/fails()")))
    }

    /// A nested test's own case beats a `System Failures` case a crash message names it in.
    @Test func aNestedIDBeatsACrashCase() {
        let crash = TestID(xcresultID: "xctest (1) encountered an error")
        let lookup = TestLookup(cases: [TestID(xcresultID: "Outer/Inner/fails()"): [], crash: []], crashCases: [TestID(suite: "Inner", name: "fails"): crash])
        #expect(lookup.resolution(of: TestID(suite: "Inner", name: "fails")) == .found(TestID(xcresultID: "Outer/Inner/fails()")))
    }
}

extension TestLookup {
    /// The bundle's ids alone, with no cases to read.
    init(ids: Set<TestID>) {
        self.init(cases: Dictionary(uniqueKeysWithValues: ids.map { ($0, []) }))
    }
}
