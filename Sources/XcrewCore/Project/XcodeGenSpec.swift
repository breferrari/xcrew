import Foundation

/// The specs an XcodeGen spec includes, which XcodeGen reads with it: an edit to any of them changes the project. A reader
/// of the top-level `include` key alone, in the forms XcodeGen's ProjectSpec documents, since the package takes no YAML
/// dependency; the rest of a spec is never read. Paths resolve as XcodeGen's `SpecFile` resolves them (docs/findings.md,
/// *XcodeGen's included specs*).
enum XcodeGenSpec {
    /// One entry of `include`: a path, or an object with `relativePaths` and `enable`.
    struct Include: Sendable, Equatable {
        let path: String
        var relativePaths = true
        var enable = true
    }

    /// Whether XcodeGen reads the file at `path`, a canonical path, for `spec`: the spec itself or one it includes, at any
    /// depth. Includes are walked as XcodeGen walks them, depth first in the order written, and each spec is read once,
    /// on its first route, which also ends a cycle.
    static func reads(_ path: String, for spec: URL) -> Bool {
        var seen: Set<String> = []
        var pending = [(base: spec.deletingLastPathComponent(), relative: "", path: spec.lastPathComponent)]
        while let next = pending.popLast() {
            let file = joined(next.base, next.path)
            let canonical = ProjectLayout.canonical(file)
            if canonical == path { return true }
            guard seen.insert(canonical).inserted, let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let children = includes(in: text).filter(\.enable).map { include in
                include.relativePaths
                    ? (base: joined(next.base, next.relative), relative: (include.path as NSString).deletingLastPathComponent, path: include.path)
                    : (base: next.base, relative: "", path: include.path)
            }
            pending.append(contentsOf: children.reversed())
        }
        return false
    }

    /// A path joined to a folder as XcodeGen's paths join: an absolute path stands alone.
    static func joined(_ folder: URL, _ path: String) -> URL {
        path.hasPrefix("/") ? URL(fileURLWithPath: path) : folder.appending(path: path)
    }

    /// The entries of a spec's top-level `include` key: a path, a flow list, a flow mapping, or a block list of paths and
    /// mappings, written below the key or at its own indent. An entry that names a variable, which XcodeGen expands from
    /// the environment, is left out: xcrew can't know it at edit time.
    static func includes(in spec: String) -> [Include] {
        let lines = spec.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        guard let start = lines.firstIndex(where: { $0.hasPrefix("include:") }) else { return [] }
        let rest = lines[(start + 1)...]
        let inline = scalar(String(lines[start].dropFirst("include:".count)))
        let entries: [[String: String]]
        if let open = inline.first, open == "[" || open == "{" {
            // A flow collection may run across lines, to its closing bracket.
            let close: Character = open == "[" ? "]" : "}"
            var text = inline
            for line in rest where !text.contains(close) { text += " " + line }
            let inside = String(text.dropFirst().prefix { $0 != close })
            entries = open == "[" ? flowItems(inside).map(entry) : [mapping(inside)]
        } else if !inline.isEmpty {
            entries = [["path": inline]]
        } else {
            var block: [[String: String]] = []
            for line in rest {
                let content = line.trimmingCharacters(in: .whitespaces)
                if content.isEmpty || content.hasPrefix("#") { continue }
                // The list ends at the next key: a line at the top that isn't one of its items.
                guard line.first?.isWhitespace == true || content.hasPrefix("- ") else { break }
                if content.hasPrefix("- ") {
                    block.append(entry(String(content.dropFirst(2))))
                } else if !block.isEmpty {
                    block[block.count - 1].merge(mapping(content)) { _, new in new }
                }
            }
            entries = block
        }
        return entries.compactMap { entry in
            guard let path = entry["path"], !path.isEmpty, !path.contains("${") else { return nil }
            guard let relativePaths = flag(entry["relativePaths"]), let enable = flag(entry["enable"]) else { return nil }
            return Include(path: path, relativePaths: relativePaths, enable: enable)
        }
    }

    /// One item of a list: a flow mapping, a `key: value` that starts a block mapping, or a path.
    static func entry(_ item: String) -> [String: String] {
        let item = item.trimmingCharacters(in: .whitespaces)
        if item.hasPrefix("{") { return mapping(String(item.dropFirst().prefix { $0 != "}" })) }
        return item.contains(": ") || item.hasSuffix(":") ? mapping(item) : ["path": scalar(item)]
    }

    /// The items of a flow collection's inside, split at the commas outside any nested mapping.
    static func flowItems(_ inside: String) -> [String] {
        var items: [String] = []
        var current = ""
        var depth = 0
        for character in inside {
            if character == "{" { depth += 1 } else if character == "}" { depth -= 1 }
            if character == ",", depth == 0 {
                items.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        return (items + [current]).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// `key: value` pairs, one per line or comma-separated in a flow mapping.
    static func mapping(_ text: String) -> [String: String] {
        var pairs: [String: String] = [:]
        for pair in flowItems(text) {
            guard let colon = pair.firstIndex(of: ":") else { continue }
            pairs[pair[..<colon].trimmingCharacters(in: .whitespaces)] = scalar(String(pair[pair.index(after: colon)...]))
        }
        return pairs
    }

    /// A YAML scalar without its comment or quotes; a comment alone is no value.
    static func scalar(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespaces)
        if let quote = value.first, quote == "\"" || quote == "'", let end = value.dropFirst().firstIndex(of: quote) {
            return String(value[value.index(after: value.startIndex)..<end])
        }
        if value.hasPrefix("#") { return "" }
        if let comment = value.range(of: " #") { value = String(value[..<comment.lowerBound]) }
        return value.trimmingCharacters(in: .whitespaces)
    }

    /// The words XcodeGen's YAML library, Yams, resolves to a boolean.
    static let yamlBooleans: [String: Bool] = Dictionary(uniqueKeysWithValues: ["yes", "true", "on"].flatMap { word in
        [word, word.capitalized, word.uppercased()].map { ($0, true) }
    } + ["no", "false", "off"].flatMap { word in [word, word.capitalized, word.uppercased()].map { ($0, false) } })

    /// An include's flag as XcodeGen reads it: a YAML boolean, or other text as `NSString.boolValue` reads it. Absent,
    /// or a number or null, which are neither, it keeps its default: true for both flags. Nothing for a variable.
    static func flag(_ value: String?) -> Bool? {
        guard let value, !["", "~", "null", "Null", "NULL"].contains(value), Double(value) == nil else { return true }
        if value.contains("${") { return nil }
        return yamlBooleans[value] ?? NSString(string: value).boolValue
    }
}
