import Foundation

/// An app's accessibility hierarchy as XCTest attaches it when a query fails, slimmed for Claude: one line per element
/// that names something, indented by depth.
struct UIHierarchy: Sendable, Equatable {
    struct Element: Sendable, Equatable {
        let depth: Int
        let type: String
        let label: String?
        let identifier: String?
        let value: String?

        var namesSomething: Bool { label != nil || identifier != nil || value != nil }
    }

    let elements: [Element]

    /// The hierarchy in `text`, by its shape: every line an element. Nil for text in any other shape.
    init?(text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        // A line as XCTest writes an element: its type, its address, then its frame and attributes.
        let element = /( *)([A-Za-z][A-Za-z ()]*?), 0x[0-9A-Fa-f]+(.*)/
        var elements: [Element] = []
        for line in lines {
            guard let match = line.wholeMatch(of: element) else { return nil }
            let rest = String(match.3)
            func attribute(_ name: String) -> String? {
                rest.range(of: ", \(name): '").flatMap { Self.quoted(rest[$0.upperBound...]) }.flatMap { $0.isEmpty ? nil : $0 }
            }
            elements.append(Element(depth: match.1.count / 2, type: String(match.2), label: attribute("label"), identifier: attribute("identifier"), value: attribute("value")))
        }
        guard !elements.isEmpty else { return nil }
        self.elements = elements
    }

    /// The text up to the closing quote of a `'…'` value whose opening quote is already read, with `\'` unescaped.
    static func quoted(_ text: Substring) -> String? {
        var value = ""
        var escaped = false
        for character in text {
            if escaped {
                value.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "'" {
                return value
            } else {
                value.append(character)
            }
        }
        return nil
    }

    /// The elements that name something, as lines, `most` at most, with the element `query` names marked; how many
    /// more there are, and whether the query's element is among them all. An element that names nothing is left out,
    /// and its children move up to its place.
    func lines(query: UIQuery?, most: Int) -> (lines: [String], more: Int, found: Bool) {
        var shown: [String] = []
        var found = false
        // The depths of the named elements above the current one, as XCTest indented them.
        var named: [Int] = []
        for element in elements {
            while let last = named.last, last >= element.depth { named.removeLast() }
            guard element.namesSomething else { continue }
            let isQueried = query.map { element.type == $0.type && (element.identifier == $0.text || element.label == $0.text) } ?? false
            found = found || isQueried
            let head = element.type + (element.label.map { " \"\($0)\"" } ?? "")
            let extras = [element.identifier.map { "identifier \"\($0)\"" }, element.value.flatMap { $0 == element.label ? nil : "value \"\($0)\"" }].compactMap(\.self)
            shown.append(String(repeating: "  ", count: named.count) + ([head] + extras).joined(separator: ", ") + (isQueried ? "   ← the query" : ""))
            named.append(element.depth)
        }
        return (Array(shown.prefix(most)), max(0, shown.count - most), found)
    }
}
