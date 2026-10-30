import Foundation

/// What a failing UI test asked for: the text it matched elements by, and their type, as XCTest names them in its steps
/// (`Tap "Continue" Button`, `Waiting 2.0s for "Done" StaticText to exist`).
struct UIQuery: Sendable, Equatable {
    let text: String
    let type: String
}

extension UIQuery {
    /// Steps before the failure searched for its query: the failing check's own wait, and XCTest's step after it. A
    /// query a step further back succeeded, so it isn't the one that failed.
    static let stepsSearched = 2

    /// The query `failure` names, or else the last of `steps`, among the last few, that names one; nil when none does.
    /// An element type is a word like `Button` or `StaticText`; a predicate's `IN` isn't one.
    init?(failure: String, steps: [String]) {
        let named = /"((?:[^"\\]|\\.)*)" ([A-Z][a-z][A-Za-z]*)/
        guard let match = ([failure] + steps.suffix(Self.stepsSearched).reversed()).lazy.compactMap({ $0.firstMatch(of: named) }).first else { return nil }
        self.init(text: String(match.1), type: String(match.2))
    }
}
