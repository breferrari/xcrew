import Foundation

extension ConfigRenderer {
    /// A config's session defaults: the lines of `sessionDefaults`, and of each profile under `sessionDefaultsProfiles`
    /// by its name, each block's lines with the block's own indent taken off. At whatever indent the file uses; a
    /// blank or comment line ends nothing, and a comment after a profile's name isn't part of it.
    static func sessions(in yaml: String) -> (global: [String]?, profiles: [(name: String, lines: [String])]) {
        var global: [String]?
        var profiles: [(name: String, lines: [String])] = []
        var section = ""
        var nameIndent: Int?
        var bodyIndent: Int?
        for line in yaml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = line.prefix { $0 == " " }.count
            if indent == 0 {
                section = key(of: trimmed) ?? ""
                (nameIndent, bodyIndent) = (nil, nil)
                if section == "sessionDefaults" { global = [] }
                continue
            }
            if section == "sessionDefaults" {
                bodyIndent = bodyIndent ?? indent
                global?.append(String(line.dropFirst(min(indent, bodyIndent ?? 0))))
            } else if section == "sessionDefaultsProfiles" {
                if nameIndent == nil || indent <= nameIndent ?? 0, let name = key(of: trimmed) {
                    (nameIndent, bodyIndent) = (indent, nil)
                    profiles.append((name, []))
                } else if !profiles.isEmpty {
                    bodyIndent = bodyIndent ?? indent
                    profiles[profiles.count - 1].lines.append(String(line.dropFirst(min(indent, bodyIndent ?? 0))))
                }
            }
        }
        return (global, profiles)
    }

    /// The key a mapping line opens with, unquoted: `'my: app': # a note` is `my: app`. Nil for a line that isn't one.
    static func key(of line: some StringProtocol) -> String? {
        let text = line.trimmingCharacters(in: .whitespaces)
        if let quote = text.first, quote == "'" || quote == "\"", let close = closingQuote(in: Substring(text)) {
            let after = text[text.index(after: close)...]
            return after.hasPrefix(":") ? unquoted(String(text[...close])) : nil
        }
        guard let colon = text.range(of: ":"), colon.upperBound == text.endIndex || text[colon.upperBound] == " " else { return nil }
        return String(text[..<colon.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    /// The text after a mapping line's key, as `key(of:)` reads the key; empty when the value is on the lines below.
    static func rest(of line: some StringProtocol) -> String {
        let text = line.trimmingCharacters(in: .whitespaces)
        var start = text.startIndex
        if let quote = text.first, quote == "'" || quote == "\"", let close = closingQuote(in: Substring(text)) { start = text.index(after: close) }
        guard let colon = text[start...].range(of: ":") else { return "" }
        return text[colon.upperBound...].trimmingCharacters(in: .whitespaces)
    }

    /// A YAML scalar's text, quotes and a trailing comment taken off, and whether it was quoted; nil when there's none.
    /// In single quotes `''` is a quote; a plain scalar ends at ` #`, a `#` alone being all comment.
    static func scalar(_ text: some StringProtocol) -> (value: String, isQuoted: Bool)? {
        let rest = text.trimmingCharacters(in: .whitespaces)
        guard let quote = rest.first, quote == "'" || quote == "\"" else {
            guard !rest.hasPrefix("#") else { return nil }
            let plain = (rest.range(of: " #").map { String(rest[..<$0.lowerBound]) } ?? rest).trimmingCharacters(in: .whitespaces)
            return plain.isEmpty ? nil : (plain, false)
        }
        guard let close = closingQuote(in: Substring(rest)) else { return nil }
        return (unquoted(String(rest[...close])), true)
    }

    /// The quote that closes the one `text` opens with; in single quotes, `''` is an escaped one.
    static func closingQuote(in text: Substring) -> Substring.Index? {
        guard let quote = text.first else { return nil }
        var index = text.index(after: text.startIndex)
        while index < text.endIndex {
            if text[index] == quote {
                let next = text.index(after: index)
                if quote == "'", next < text.endIndex, text[next] == "'" {
                    index = text.index(after: next)
                    continue
                }
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// YAML 1.2's null as a plain scalar: `null`, `~`, in any case YAML allows.
    static func isNull(_ scalar: (value: String, isQuoted: Bool)) -> Bool {
        !scalar.isQuoted && ["null", "Null", "NULL", "~"].contains(scalar.value)
    }

    /// The items of an inline list or map, `[a, 'b']` or `{A: b}`, split at the commas outside quotes; nil for text that
    /// isn't one.
    static func inlineItems(_ text: String, open: Character, close: Character) -> [String]? {
        guard text.first == open, text.last == close else { return nil }
        var items: [String] = []
        var current = ""
        var quote: Character?
        for character in text.dropFirst().dropLast() {
            if let open = quote {
                current.append(character)
                if character == open { quote = nil }
            } else if character == "'" || character == "\"" {
                quote = character
                current.append(character)
            } else if character == "," {
                items.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        items.append(current)
        return items.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
