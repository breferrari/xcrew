import Foundation

/// What a failing UI test asked for: the text it matched elements by, and their type, as XCTest names them in its steps
/// (`Tap "Continue" Button`, `Waiting 2.0s for "Done" StaticText to exist`).
struct UIQuery: Sendable, Equatable {
    let text: String
    let type: String

    init(text: String, type: String) {
        self.text = text
        self.type = type
    }

    /// The query `failure` names, or else the last of `steps` that names one; nil when none does.
    init?(failure: String, steps: [String]) {
        let named = /"((?:[^"\\]|\\.)*)" ([A-Z][A-Za-z]*)/
        guard let match = ([failure] + steps.reversed()).lazy.compactMap({ $0.firstMatch(of: named) }).first else { return nil }
        self.init(text: String(match.1), type: String(match.2))
    }
}
