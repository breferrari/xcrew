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
        let runs: [(String, [String]?)] = [("Plan A · iPhone 18, iOS 27.2", Self.elements), ("Plan B · iPhone 18, iOS 27.2", Self.elements), ("Plan C · iPhone 18, iOS 27.2", Self.elements), ("Plan D · iPhone 18, iOS 27.2", other)]
        #expect(Look.elements(of: runs) == [
            Self.elements,
            ["on screen: the same as under Plan A · iPhone 18, iOS 27.2"],
            ["on screen: the same as under Plan A · iPhone 18, iOS 27.2"],
            other,
        ])
    }

    /// A run whose elements aren't listed, as one that attached nothing, is no run another's can be the same as.
    @Test func aRunWhoseElementsArentListedIsNoneToBeTheSameAs() {
        let runs: [(String, [String]?)] = [("Plan A · iPhone 18, iOS 27.2", nil), ("Plan B · iPhone 18, iOS 27.2", Self.elements), ("Plan C · iPhone 18, iOS 27.2", Self.elements)]
        #expect(Look.elements(of: runs) == [nil, Self.elements, ["on screen: the same as under Plan B · iPhone 18, iOS 27.2"]])
    }

    /// A screen past the elements listed ends with how many more there are and where its own hierarchy is: two runs
    /// whose elements are the same say so though each names its own file.
    @Test func elementsTheSameButForWhereTheRestAreAreSaidOnce() {
        let more = { (path: String) in Self.elements + ["  and 12 more in \(path)"] }
        let runs: [(String, [String]?)] = [("Plan A · iPhone 18, iOS 27.2", more("/images/run/A.txt")), ("Plan B · iPhone 18, iOS 27.2", more("/images/run/B.txt"))]
        #expect(Look.elements(of: runs) == [more("/images/run/A.txt"), ["on screen: the same as under Plan A · iPhone 18, iOS 27.2"]])
    }

    /// A run that kept no hierarchy lists no element, so it says so under each run rather than "the same as" another.
    @Test func noHierarchyKeptIsSaidUnderEachRun() {
        let none = ["on screen: no hierarchy kept; XCTest attaches one when a query fails"]
        let runs: [(String, [String]?)] = [("Plan A · iPhone 18, iOS 27.2", none), ("Plan B · iPhone 18, iOS 27.2", none)]
        #expect(Look.elements(of: runs) == [none, none])
    }

    static func hierarchy() throws -> FailureHierarchy {
        FailureHierarchy(content: .read(try #require(UIHierarchy(text: UIHierarchyTests.captured))), path: "hierarchy.txt")
    }
    static let appsOnly = "the elements below are the app's only; a system alert, as a permission request, shows only in the screenshot"

    /// A query that found nothing, with a screenshot kept: a system alert covering the app is another process's, so the
    /// list can't show it and the screenshot can.
    @Test func aQueryThatFoundNothingBesideAScreenshotSaysTheListIsTheAppsOnly() throws {
        let lines = Look.hierarchyLines(try Self.hierarchy(), query: UIQuery(text: "checkout", type: "Button"), screenshot: true)
        #expect(lines.prefix(2) == [Self.appsOnly, #"on screen, nothing the query's "checkout" Button matches:"#])
    }

    /// With no screenshot to look at, or a query that found its element, there's nothing to say.
    @Test func noScreenshotOrAFoundQueryAddsNothing() throws {
        #expect(!Look.hierarchyLines(try Self.hierarchy(), query: UIQuery(text: "checkout", type: "Button"), screenshot: false).contains(Self.appsOnly))
        #expect(!Look.hierarchyLines(try Self.hierarchy(), query: UIQuery(text: "continue", type: "Button"), screenshot: true).contains(Self.appsOnly))
    }
}
