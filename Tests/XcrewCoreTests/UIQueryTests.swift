import Foundation
import Testing
@testable import XcrewCore

/// The element a failing UI test asked for, as XCTest names it in its failure or its steps.
@Suite struct UIQueryTests {
    /// The query a failure names: in its own message, or in one of the two steps just before it. A query a step
    /// further back passed, so it isn't the one that failed.
    @Test(arguments: [
        (#"Failed to tap "checkout" Button: No matches found for Elements matching predicate '"checkout" IN identifiers'"#, [String](), UIQuery(text: "checkout", type: "Button")),
        ("XCTAssertTrue failed", [#"Open dev.xcrew.testbed.App"#, #"Waiting 2.0s for "Plan A" StaticText to exist"#, "Collecting debug information to assist test failure triage"], UIQuery(text: "Plan A", type: "StaticText")),
        ("XCTAssertTrue failed", ["Set Up"], nil),
        ("XCTAssertTrue failed", [#"Tap "Continue" Button"#, "Set Up", "Open App"], nil),
        (#"No matches found for Elements matching predicate '"checkout" IN identifiers'"#, [String](), nil),
    ])
    func theQueryIsTheOneTheFailureOrItsLastStepsName(failure: String, steps: [String], query: UIQuery?) {
        #expect(UIQuery(failure: failure, steps: steps) == query)
    }
}
