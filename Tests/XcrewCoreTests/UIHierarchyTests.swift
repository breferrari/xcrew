import Foundation
import Testing
@testable import XcrewCore

/// The app's accessibility hierarchy as XCTest attaches it when a query fails, slimmed for Claude.
@Suite struct UIHierarchyTests {
    /// XCTest's text, as the test bed's capture holds it (`captures/uitests`, one failed run of `testMissingElement`).
    static let captured = """
        Application, 0x105871180, pid: 26159, label: 'App' <App element pid: 26159>
          Window (Main), 0x105871540, {{0.0, 0.0}, {440.0, 956.0}} <AX element pid: 26159, elementOrHash.elementID: 4364746752.4>
            Other, 0x105871400, {{0.0, 0.0}, {440.0, 956.0}} <AX element pid: 26159, elementOrHash.elementID: 4413712384.5>
              Other, 0x105871a40, {{0.0, 0.0}, {440.0, 956.0}} <AX element pid: 26159, elementOrHash.elementID: 4413713664.6>
                StaticText, 0x105871e00, {{184.5, 459.5}, {71.0, 20.3}}, identifier: 'title', label: 'Welcome' <AX element pid: 26159, elementOrHash.elementID: 4416146400.9>
                StaticText, 0x105872080, {{196.0, 481.8}, {48.0, 20.3}}, identifier: 'plan', label: 'Plan B' <AX element pid: 26159, elementOrHash.elementID: 4416146240.10>
                Button, 0x1058721c0, {{185.7, 504.3}, {68.7, 20.3}}, identifier: 'continue', label: 'Continue' <AX element pid: 26159, elementOrHash.elementID: 4416146560.11>
        """

    /// Each element on a line of its own: its type, label, identifier and value, indented by depth; frames, addresses
    /// and the containers that name nothing are left out, their children moved up.
    @Test func eachNamedElementIsALineIndentedByDepth() throws {
        let hierarchy = try #require(UIHierarchy(text: Self.captured))
        #expect(hierarchy.lines(query: nil, most: 10).lines == [
            #"Application "App""#,
            #"  StaticText "Welcome", identifier "title""#,
            #"  StaticText "Plan B", identifier "plan""#,
            #"  Button "Continue", identifier "continue""#,
        ])
    }

    /// The element a failing query asked for is marked, matched by identifier or label as XCUITest matches a subscript.
    @Test func theQueriedElementIsMarked() throws {
        let hierarchy = try #require(UIHierarchy(text: Self.captured))
        let shown = hierarchy.lines(query: UIQuery(text: "continue", type: "Button"), most: 10)
        #expect(shown.lines.last == #"  Button "Continue", identifier "continue"   ← the query"#)
        #expect(shown.found)
        #expect(!hierarchy.lines(query: UIQuery(text: "checkout", type: "Button"), most: 10).found)
    }

    /// A value is shown when it says more than the label; quotes in a label survive.
    @Test func aValueAndQuotesInALabelAreKept() throws {
        let hierarchy = try #require(UIHierarchy(text: """
            Application, 0x1, pid: 1, label: 'App'
              TextField, 0x2, {{0.0, 0.0}, {1.0, 1.0}}, identifier: 'email', label: 'Email', value: 'a@b.c'
              StaticText, 0x3, {{0.0, 0.0}, {1.0, 1.0}}, label: 'It\\'s, done'
            """))
        #expect(hierarchy.lines(query: nil, most: 10).lines == [
            #"Application "App""#,
            #"  TextField "Email", identifier "email", value "a@b.c""#,
            #"  StaticText "It's, done""#,
        ])
    }

    /// Past the budget, the rest is counted.
    @Test func aLongHierarchyIsCutToItsBudget() throws {
        let rows = (1...12).map { "  Button, 0x\($0), {{0.0, 0.0}, {1.0, 1.0}}, label: 'B\($0)'" }
        let hierarchy = try #require(UIHierarchy(text: (["Application, 0x0, pid: 1, label: 'App'"] + rows).joined(separator: "\n")))
        let shown = hierarchy.lines(query: nil, most: 5)
        #expect(shown.lines.count == 5)
        #expect(shown.more == 8)
    }

    /// XCTest may leave an apostrophe in a label unescaped, and print a value without quotes; a label's text can hold
    /// what looks like another attribute.
    @Test func attributesAreReadWhateverTheirQuoting() throws {
        let hierarchy = try #require(UIHierarchy(text: """
            Application, 0x1, pid: 1, label: 'App'
              Button, 0x2, {{0.0, 0.0}, {1.0, 1.0}}, label: 'Don't have an account?'
              Switch, 0x3, {{0.0, 0.0}, {1.0, 1.0}}, identifier: 'wifi', label: 'Wi-Fi', value: 1 <AX element pid: 1>
              StaticText, 0x4, {{0.0, 0.0}, {1.0, 1.0}}, identifier: 'note, label: 'x'', label: 'Note'
            """))
        #expect(hierarchy.lines(query: nil, most: 10).lines == [
            #"Application "App""#,
            #"  Button "Don't have an account?""#,
            #"  Switch "Wi-Fi", identifier "wifi", value "1""#,
            #"  StaticText "Note", identifier "note, label: 'x'""#,
        ])
    }

    /// The queried element is shown even past the budget, so its mark is never cut.
    @Test func theQueriedElementIsShownPastTheBudget() throws {
        let rows = (1...12).map { "  Button, 0x\($0), {{0.0, 0.0}, {1.0, 1.0}}, label: 'B\($0)'" }
        let hierarchy = try #require(UIHierarchy(text: (["Application, 0x0, pid: 1, label: 'App'"] + rows).joined(separator: "\n")))
        let shown = hierarchy.lines(query: UIQuery(text: "B10", type: "Button"), most: 5)
        #expect(shown.lines.last == #"  Button "B10"   ← the query"#)
        #expect(shown.more == 7)
    }

    /// Text in another shape isn't a hierarchy: a query's debug description, as XCTest attaches beside it.
    @Test func otherTextIsNotAHierarchy() {
        #expect(UIHierarchy(text: "Query chain:\n →Find: Target Application 'dev.xcrew.testbed.App'\n  ↪︎Find: Descendants matching type StaticText") == nil)
        #expect(UIHierarchy(text: "") == nil)
    }
}
