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
        // A line as XCTest writes an element: its type, its address, then its frame and attributes.
        let element = /( *)([A-Za-z][A-Za-z ()]*?), 0x[0-9A-Fa-f]+(.*)/
        var elements: [Element] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let match = line.wholeMatch(of: element) else { return nil }
            let attributes = Self.attributes(match.3)
            let named = { (key: String) in attributes[key].flatMap { $0.isEmpty ? nil : $0 } }
            elements.append(Element(depth: match.1.count / 2, type: String(match.2), label: named("label"), identifier: named("identifier"), value: named("value")))
        }
        guard !elements.isEmpty else { return nil }
        self.elements = elements
    }

    /// The `, key: value` attributes after an element's address, read left to right so a quoted value's text is never
    /// taken for another attribute. A value is quoted (`'…'`, its own apostrophes escaped or not) or bare (`1`).
    static func attributes(_ rest: Substring) -> [String: String] {
        var found: [String: String] = [:]
        var rest = rest
        // XCTest's own note on the element, `<AX element …>`, ends the line.
        if let note = rest.firstMatch(of: #/ <[^<>']*>$/#) { rest = rest[..<note.range.lowerBound] }
        while let key = rest.firstMatch(of: #/, ([A-Za-z]+): /#) {
            let value = rest[key.range.upperBound...]
            if value.first == "'", let (text, end) = quoted(value.dropFirst()) {
                found[String(key.1)] = text
                rest = rest[end...]
            } else {
                let end = value.firstRange(of: ", ")?.lowerBound ?? value.endIndex
                found[String(key.1)] = String(value[..<end])
                rest = value[end...]
            }
        }
        return found
    }

    /// The text of a `'…'` value whose opening quote is already read, and where it ends: at the quote that's followed by
    /// the next attribute or the line's end, so an apostrophe inside it, escaped as `\'` or not, is kept.
    static func quoted(_ text: Substring) -> (String, Substring.Index)? {
        var value = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == "\\", next < text.endIndex, text[next] == "'" {
                value.append("'")
                index = text.index(after: next)
                continue
            }
            if character == "'", text[next...].isEmpty || text[next...].prefixMatch(of: #/, [A-Za-z]+: /#) != nil {
                return (value, next)
            }
            value.append(character)
            index = next
        }
        return nil
    }

    /// The elements that name something, as lines, `most` at most, with the element `query` names marked; how many
    /// more there are, and whether the query's element is among them all. An element that names nothing is left out,
    /// and its children move up to its place.
    func lines(query: UIQuery?, most: Int) -> (lines: [String], more: Int, found: Bool) {
        var shown: [String] = []
        var queried: Int?
        // The depths of the named elements above the current one, as XCTest indented them.
        var named: [Int] = []
        for element in elements {
            while let last = named.last, last >= element.depth { named.removeLast() }
            guard element.namesSomething else { continue }
            let isQueried = query.map { element.type == $0.type && (element.identifier == $0.text || element.label == $0.text) } ?? false
            if isQueried, queried == nil { queried = shown.count }
            let head = element.type + (element.label.map { " \"\($0)\"" } ?? "")
            let extras = [element.identifier.map { "identifier \"\($0)\"" }, element.value.flatMap { $0 == element.label ? nil : "value \"\($0)\"" }].compactMap(\.self)
            shown.append(String(repeating: "  ", count: named.count) + ([head] + extras).joined(separator: ", ") + (isQueried ? "   ← the query" : ""))
            named.append(element.depth)
        }
        // The queried element is shown wherever it falls, so its mark is never cut.
        let past = queried.flatMap { $0 >= most ? [shown[$0]] : nil } ?? []
        let lines = Array(shown.prefix(most)) + past
        return (lines, shown.count - lines.count, queried != nil)
    }
}
