import Foundation

/// The plugin directory's rule for a hooks module, as it words it when it refuses one: "Write each call on the capability
/// object as `$.noun.method(...)`, each registration as `on("event", hook)` on a line of its own, and pass `$` or the `on`
/// function only as one whole argument to a function declared at the top of the same file." It reads a module's source
/// with its comments, strings and regular expressions blanked, so only code is read, and lists each use that breaks it.
/// Beyond the words, as the directory read the mod when it blocked it (docs/findings.md, *How the plugin directory reads
/// a plugin*): a call `$` goes to is a plain call, with nothing chained on what it returns, and the mods API is named `$`
/// wherever a hook or a function takes it. `$` may also go whole to the API's own `read` and `update`.
struct DirectoryRule {
    /// A use the rule refuses: its line, counted from 1, and the line's code.
    struct Breach: Equatable, CustomStringConvertible {
        let line: Int
        let code: String
        var description: String { "\(line): \(code)" }
    }

    /// The plugin's own properties, which the API declares as values, not methods: `CoreEngineInterface.plugin` in the
    /// API types (`.claude-plugin/types/claude-code/index.d.ts`), "This plugin, as loaded: its manifest name and its
    /// directory". A plugin can read its own directory no other way, so the rule's "each call" doesn't reach them.
    static let pluginProperties: Set = ["name", "root"]

    /// How far around a use the checks here look.
    static let reach = 200

    /// Each use of `$` or `on` in `source` that the rule refuses, and each parameter that takes the API under another name.
    static func breaches(in source: String) -> [Breach] {
        let text = blanked(source)
        let code = Array(text)
        let lines = source.components(separatedBy: "\n")
        let topLevel = Set(text.matches(of: /(?m)^(?:export\s+)?(?:async\s+)?function\*?\s+([A-Za-z_]\w*)/).map { String($0.1) })
        let fromAPI = Set(source.matches(of: /import\s*\{([^}]*)\}\s*from\s*'claude-code'/).flatMap { $0.1.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } })
        let refused = ["$", "on"].flatMap { name in
            occurrences(of: name, in: code).filter { !isAllowed(name, at: $0, in: code, callees: topLevel.union(fromAPI)) }
        } + misnamedAPI(in: text)
        return Set(refused.map { index in code[..<index].filter { $0 == "\n" }.count + 1 }).sorted()
            .map { Breach(line: $0, code: lines[$0 - 1].trimmingCharacters(in: .whitespaces)) }
    }

    /// Where a hook or a function takes the mods API under a name other than `$`: a parameter typed `EngineInterface`,
    /// or a registration's hook whose first parameter is another name or destructured.
    static func misnamedAPI(in text: String) -> [Int] {
        let typed = text.matches(of: /([A-Za-z_$][\w$]*|\})\s*:\s*EngineInterface\b/).filter { $0.1 != "$" }.map(\.range.lowerBound)
        let hooks = text.matches(of: /(?m)^[ \t]*on\(\s*'[^']*'\s*,(?:\s*\{[^{}]*\}\s*,)?\s*(?:async\s+)?(?:\(\s*([^\s,):]*)|([A-Za-z_$][\w$]*)\s*=>)/)
            .filter { match in (match.1 ?? match.2).map { !$0.isEmpty && $0 != "$" } ?? false }.map(\.range.lowerBound)
        return (typed + hooks).map { text.distance(from: text.startIndex, to: $0) }
    }

    /// Where `name` stands as a whole identifier in `code`, not part of a longer one or a property after a `.`.
    static func occurrences(of name: String, in code: [Character]) -> [Int] {
        let word = Array(name)
        return code.indices.filter { index in
            guard code[index...].starts(with: word) else { return false }
            if index > 0, isIdentifier(code[index - 1]) || code[index - 1] == "." { return false }
            return index + word.count == code.count || !isIdentifier(code[index + word.count])
        }
    }

    static func isIdentifier(_ character: Character) -> Bool { character.isLetter || character.isNumber || character == "_" || character == "$" }

    /// Whether the use of `name` at `index` is one the rule reads: an API call or a plugin property for `$`, a
    /// registration on its own line for `on`, a parameter, a property key named `on`, or one whole argument to one of
    /// `callees` in a plain call.
    static func isAllowed(_ name: String, at index: Int, in code: [Character], callees: Set<String>) -> Bool {
        let before = window(code, before: index), after = window(code, after: index + name.count)
        if isParameter(at: index, name: name, code: code) { return true }
        switch name {
        case "$":
            if after.firstMatch(of: /^\.[A-Za-z_]\w*\.[A-Za-z_]\w*\s*(?:<[^()]*>)?\(/) != nil { return true }
            if let property = after.firstMatch(of: /^\.plugin\.(\w+)\b(?!\s*\()/), pluginProperties.contains(String(property.1)) { return true }
        default:
            if after.firstMatch(of: /^\s*\(/) != nil { return before.firstMatch(of: /(?:^|\n)[ \t]*$/) != nil }
            if after.firstMatch(of: /^\s*:/) != nil, before.firstMatch(of: /[{,]\s*$/) != nil { return true }
        }
        guard before.firstMatch(of: /[(,]\s*$/) != nil, after.firstMatch(of: /^\s*[,)]/) != nil,
              let open = enclosingCallOpen(before: index, in: code), let close = enclosingCallClose(after: index, in: code),
              let callee = window(code, before: open).firstMatch(of: /(?:^|[^.\w$])([A-Za-z_$][\w$]*)\s*$/), callees.contains(String(callee.1)) else { return false }
        return window(code, after: close + 1).firstMatch(of: /^\s*(?:\??\.|\[|\(|`)/) == nil
    }

    /// Whether `name` at `index` is a parameter: the one of an arrow, `$ =>`, or one in the list an arrow or a function
    /// declares.
    static func isParameter(at index: Int, name: String, code: [Character]) -> Bool {
        let after = window(code, after: index + name.count), before = window(code, before: index)
        if after.firstMatch(of: /^\s*=>/) != nil { return true }
        guard before.firstMatch(of: /[(,]\s*$/) != nil, after.firstMatch(of: /^\s*[:,)]/) != nil,
              let open = enclosingCallOpen(before: index, in: code), let close = enclosingCallClose(after: index, in: code) else { return false }
        if window(code, after: close + 1).firstMatch(of: /^\s*(?::[^;{}()\n?]*)?=>/) != nil { return true }
        return window(code, before: open).firstMatch(of: /function\s*\*?\s*[\w$]*\s*$/) != nil
    }

    /// The code just before `index`, or just after it, as far as `reach`.
    static func window(_ code: [Character], before index: Int) -> String { String(code[max(index - reach, 0)..<index]) }
    static func window(_ code: [Character], after index: Int) -> String { String(code[min(index, code.count)..<min(index + reach, code.count)]) }

    /// The `(` that opens the brackets around `index`; nil when they're `[` or `{`.
    static func enclosingCallOpen(before index: Int, in code: [Character]) -> Int? {
        var depth = 0
        for position in stride(from: index - 1, through: 0, by: -1) {
            switch code[position] {
            case ")", "]", "}": depth += 1
            case "(", "[", "{":
                if depth == 0 { return code[position] == "(" ? position : nil }
                depth -= 1
            default: continue
            }
        }
        return nil
    }

    /// The `)` that closes the brackets around `index`; nil when they're `]` or `}`.
    static func enclosingCallClose(after index: Int, in code: [Character]) -> Int? {
        var depth = 0
        for position in index..<code.count {
            switch code[position] {
            case "(", "[", "{": depth += 1
            case ")", "]", "}":
                if depth == 0 { return code[position] == ")" ? position : nil }
                depth -= 1
            default: continue
            }
        }
        return nil
    }

    /// `source` with each comment, string, template text and regular expression's characters spaced out, its lines kept,
    /// and the code inside a template's `${…}` kept.
    static func blanked(_ source: String) -> String {
        let characters = Array(source)
        var out: [Character] = []
        var index = 0
        // For each template open, `nil` while in its text, else how many braces deep its `${…}` code is.
        var templates: [Int?] = []
        var previous: Character = "\n"
        func blank(_ range: Range<Int>) { out += characters[range].map { $0 == "\n" ? "\n" : " " } }
        func startsRegularExpression() -> Bool {
            if "(,=:[!&|?{};+-*%<>~^\n".contains(previous) { return true }
            return String(out.suffix(12)).firstMatch(of: /(?:^|[^\w$])(?:return|typeof|case|of|in)\s*$/) != nil
        }
        // A string or regular expression from `index`, closed by `closer` on its line: blanked between, and the newline
        // that ends an unclosed one kept.
        func literal(closedBy closer: Character, readsClasses: Bool) {
            var end = index + 1, inClass = false
            while end < characters.count, characters[end] != "\n" {
                if characters[end] == "\\" { end += 2; continue }
                if readsClasses, characters[end] == "[" {
                    inClass = true
                } else if readsClasses, characters[end] == "]" {
                    inClass = false
                } else if characters[end] == closer, !inClass {
                    break
                }
                end += 1
            }
            end = min(end, characters.count)
            out.append(characters[index]); blank((index + 1)..<end)
            if end < characters.count, characters[end] == closer { out.append(closer); end += 1 }
            previous = closer; index = end
        }
        while index < characters.count {
            let character = characters[index]
            if let open = templates.last, open == nil {
                if character == "\\" { blank(index..<min(index + 2, characters.count)); index += 2; continue }
                if character == "`" { templates.removeLast(); out.append(character); previous = character; index += 1; continue }
                if character == "$", index + 1 < characters.count, characters[index + 1] == "{" {
                    templates[templates.count - 1] = 0
                    out += [" ", "{"]; previous = "{"; index += 2; continue
                }
                blank(index..<(index + 1)); index += 1; continue
            }
            let rest = characters[index...]
            if rest.starts(with: "//") {
                let end = characters[index...].firstIndex(of: "\n") ?? characters.count
                blank(index..<end); index = end; continue
            }
            if rest.starts(with: "/*") {
                var end = index + 2
                while end + 1 < characters.count, !(characters[end] == "*" && characters[end + 1] == "/") { end += 1 }
                end = min(end + 2, characters.count)
                blank(index..<end); index = end; continue
            }
            if character == "'" || character == "\"" { literal(closedBy: character, readsClasses: false); continue }
            if character == "`" { templates.append(nil); out.append(character); index += 1; continue }
            if character == "/", startsRegularExpression() { literal(closedBy: "/", readsClasses: true); continue }
            if let depth = templates.last, let depth {
                if character == "{" { templates[templates.count - 1] = depth + 1 }
                if character == "}" {
                    if depth == 0 { templates[templates.count - 1] = nil; out.append("}"); previous = "}"; index += 1; continue }
                    templates[templates.count - 1] = depth - 1
                }
            }
            out.append(character)
            if !character.isWhitespace || character == "\n" { previous = character }
            index += 1
        }
        return String(out)
    }
}
