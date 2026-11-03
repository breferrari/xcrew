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

    /// The key a mapping line opens with, unquoted, and the text after it: `'my: app': # a note` is `my: app` and
    /// `# a note`, and `app:debug:` is `app:debug`, as YAML ends a plain key at its first `: ` or at a `:` closing the
    /// line. Nil for a line that isn't one.
    static func split(_ line: some StringProtocol) -> (key: String, rest: String)? {
        let text = line.trimmingCharacters(in: .whitespaces)
        if let quote = text.first, quote == "'" || quote == "\"", let close = closingQuote(in: Substring(text)) {
            let after = text[text.index(after: close)...]
            guard after.hasPrefix(":") else { return nil }
            return (unquoted(String(text[...close])), after.dropFirst().trimmingCharacters(in: .whitespaces))
        }
        if let colon = text.range(of: ": ") {
            return (String(text[..<colon.lowerBound]).trimmingCharacters(in: .whitespaces), text[colon.upperBound...].trimmingCharacters(in: .whitespaces))
        }
        guard text.hasSuffix(":"), text.count > 1 else { return nil }
        return (String(text.dropLast()).trimmingCharacters(in: .whitespaces), "")
    }

    static func key(of line: some StringProtocol) -> String? {
        split(line)?.key
    }

    static func rest(of line: some StringProtocol) -> String {
        split(line)?.rest ?? ""
    }

    /// The keys of a block's lines at its own indent, each with its value on its line, a value wrapped onto the lines
    /// below folded into it with one space, or else the lines below it, which hold its list or map: a list's items may
    /// sit at the key's own indent. A comment after a key whose value is below is no value. Comment lines are left out.
    static func entries(_ lines: [String]) -> [(key: String, value: String, below: [String])] {
        let lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var found: [(key: String, value: String, below: [String])] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            guard !line.hasPrefix(" "), !line.hasPrefix("-"), let (key, rest) = split(line) else { continue }
            let value = rest.hasPrefix("#") ? "" : rest
            var below: [String] = []
            while index < lines.count, lines[index].hasPrefix(" ") || (value.isEmpty && lines[index].hasPrefix("-")) {
                below.append(lines[index])
                index += 1
            }
            if value.isEmpty {
                found.append((key, "", below))
            } else {
                found.append((key, ([value] + below.map { $0.trimmingCharacters(in: .whitespaces) }).joined(separator: " "), []))
            }
        }
        return found
    }

    /// The first non-null, non-empty value of `key` among `lines`' entries.
    static func value(of key: String, among lines: [String]) -> String? {
        entries(lines).lazy.filter { $0.key == key }.compactMap { scalar($0.value) }.first { !isNull($0) && !$0.value.isEmpty }?.value
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
    /// isn't one. A quote's `''` escape reads as two quotes here, which close and reopen it, so the split is the same.
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
