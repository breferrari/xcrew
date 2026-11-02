import Foundation
import Testing
@testable import XcrewCore

/// The elements on screen at each failed run's failure, as `look` lists them under each run.
@Suite struct LookElementsTests {
    static let elements = ["on screen:", #"  Application "App""#, #"    Button "Continue", identifier "continue""#]

    /// Under a test plan of three configurations whose screens hold the same elements, the list shows once, and each
    /// later configuration says it's the same in one line; a run whose elements differ lists its own.
    @Test func elementsTheSameAsAnEarlierRunsAreSaidOnce() {
        let other = ["on screen:", #"  Application "App""#, #"    StaticText "Plan B""#]
        let runs = [("Plan A · iPhone 18, iOS 27.2", Self.elements), ("Plan B · iPhone 18, iOS 27.2", Self.elements), ("Plan C · iPhone 18, iOS 27.2", Self.elements), ("Plan D · iPhone 18, iOS 27.2", other)]
        #expect(Look.elements(of: runs) == [
            Self.elements,
            ["on screen: the same as under Plan A · iPhone 18, iOS 27.2"],
            ["on screen: the same as under Plan A · iPhone 18, iOS 27.2"],
            other,
        ])
    }
}
