import Foundation

/// The plugin directory's rule for a hooks module, as it words it when it refuses one: "Write each call on the capability
/// object as `$.noun.method(...)`, each registration as `on("event", hook)` on a line of its own, and pass `$` or the `on`
/// function only as one whole argument to a function declared at the top of the same file." It reads a module's source
/// with its comments, strings and regular expressions blanked, so only code is read, and lists each use that breaks it.
/// A `$` may also be a parameter, and go whole to the helpers the API itself exports, `read` and `update`, as the API's
/// own examples pass it. A call `$` goes to whole is read as a plain call, with nothing chained on what it returns: the
/// directory refused `await build($).catch(…)`, a call to a function declared at the top of the file, though the rule's
/// words allow it.
struct DirectoryRule {
    /// The plugin's own properties, which the API declares as values, not methods: `CoreEngineInterface.plugin` in the
    /// API types (`claude-code.d.ts`), "This plugin, as loaded: its manifest name and its directory", `name` and `root`.
    /// A plugin can read its own directory no other way, so the rule's "each call" doesn't reach them, and the directory
    /// didn't flag the mod's reads of `$.plugin.root`.
    static let documentedProperties: Set = ["name", "root"]

    /// A use the rule refuses: its line, counted from 1, and the line's code.
    struct Breach: Equatable, CustomStringConvertible {
        let line: Int
        let code: String
        var description: String { "\(line): \(code)" }
    }

    /// Each use of `$` or `on` in `source` that the rule refuses.
    static func breaches(in source: String) -> [Breach] {
        let code = Array(blanked(source))
        let text = String(code)
        let lines = source.components(separatedBy: "\n")
        let topLevel = Set(text.matches(of: /(?m)^(?:export\s+)?(?:async\s+)?function\*?\s+([A-Za-z_]\w*)/).map { String($0.1) })
        let fromAPI = Set(source.matches(of: /import\s*\{([^}]*)\}\s*from\s*'claude-code'/).flatMap { $0.1.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } })
        var found: [Breach] = []
        for name in ["$", "on"] {
            for index in occurrences(of: name, in: code) {
                if isAllowed(name, before: window(code, before: index), after: window(code, after: index + name.count), code: code, at: index, receivers: topLevel.union(fromAPI)) { continue }
                let line = code[..<index].filter { $0 == "\n" }.count + 1
                found.append(Breach(line: line, code: lines[line - 1].trimmingCharacters(in: .whitespaces)))
            }
        }
        return found.sorted { $0.line < $1.line }
    }

    /// Where `name` stands as a whole identifier in `code`, not part of a longer one or a property after a `.`.
    static func occurrences(of name: String, in code: [Character]) -> [Int] {
        let word = Array(name)
        func isIdentifier(_ character: Character) -> Bool { character.isLetter || character.isNumber || character == "_" || character == "$" }
        return code.indices.filter { index in
            guard index + word.count <= code.count, Array(code[index..<(index + word.count)]) == word else { return false }
            if index > 0, isIdentifier(code[index - 1]) || code[index - 1] == "." { return false }
            if index + word.count < code.count, isIdentifier(code[index + word.count]) { return false }
            return true
        }
    }

    static func isAllowed(_ name: String, before: String, after: String, code: [Character], at index: Int, receivers: Set<String>) -> Bool {
        // A property named `on` in an object, `{ on: … }`, is no use of the function.
        if name == "on", after.firstMatch(of: /^\s*:/) != nil, before.firstMatch(of: /[{,]\s*$/) != nil, !isParameter(at: index, name: name, code: code) { return true }
        if name == "$", after.firstMatch(of: /^\.[A-Za-z_]\w*\.[A-Za-z_]\w*\s*(?:<[^()]*>)?\(/) != nil { return true }
        if name == "$", let property = after.firstMatch(of: /^\.plugin\.(\w+)\b(?!\s*\()/), documentedProperties.contains(String(property.1)) { return true }
        if name == "on", after.firstMatch(of: /^\s*\(/) != nil {
            // A registration, on a line of its own.
            return before.firstMatch(of: /(?:^|\n)[ \t]*$/) != nil
        }
        if isParameter(at: index, name: name, code: code) { return true }
        // One whole argument: the call's callee is a function declared at the top of the file, or one of the API's.
        guard before.firstMatch(of: /[(,]\s*$/) != nil, after.firstMatch(of: /^\s*[,)]/) != nil, let open = openingParenthesis(before: index, in: code) else { return false }
        let callee = window(code, before: open).firstMatch(of: /(^|[^.\w$])([A-Za-z_$][\w$]*)\s*$/)
        guard let callee, receivers.contains(String(callee.2)), let close = closingParenthesis(after: index, in: code) else { return false }
        // A plain call: nothing is chained on what it returns, as `.catch(…)`.
        return window(code, after: close + 1).firstMatch(of: /^\s*\??\./) == nil
    }

    /// Whether `name` at `index` is a parameter: typed, as `$: EngineInterface`, the one of an arrow, `$ =>`, or one in
    /// a list an arrow or a function declares.
    static func isParameter(at index: Int, name: String, code: [Character]) -> Bool {
        let after = window(code, after: index + name.count), before = window(code, before: index)
        if after.firstMatch(of: /^\s*=>/) != nil { return true }
        guard before.firstMatch(of: /[(,]\s*$/) != nil, after.firstMatch(of: /^\s*[:,)]/) != nil, let open = openingParenthesis(before: index, in: code),
              let close = closingParenthesis(after: index, in: code) else { return false }
        if window(code, after: close + 1).firstMatch(of: /^\s*(?::[^=;{]*)?(?:=>|\{)/) != nil { return true }
        return window(code, before: open).firstMatch(of: /function\s*\*?\s*[\w$]*\s*$/) != nil
    }

    /// The code just before `index`, or just after it: as far as any check here looks.
    static func window(_ code: [Character], before index: Int) -> String { String(code[max(index - 200, 0)..<index]) }
    static func window(_ code: [Character], after index: Int) -> String { String(code[min(index, code.count)..<min(index + 200, code.count)]) }

    static func openingParenthesis(before index: Int, in code: [Character]) -> Int? {
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

    static func closingParenthesis(after index: Int, in code: [Character]) -> Int? {
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
            return String(out.suffix(12)).firstMatch(of: /(?:return|typeof|case|of|in)\s*$/) != nil
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
            if character == "'" || character == "\"" {
                var end = index + 1
                while end < characters.count, characters[end] != character, characters[end] != "\n" { end += characters[end] == "\\" ? 2 : 1 }
                out.append(character); blank((index + 1)..<min(end, characters.count))
                if end < characters.count { out.append(character) }
                previous = character; index = end + 1; continue
            }
            if character == "`" { templates.append(nil); out.append(character); index += 1; continue }
            if character == "/", startsRegularExpression() {
                var end = index + 1, inClass = false
                while end < characters.count, characters[end] != "\n" {
                    if characters[end] == "\\" { end += 2; continue }
                    if characters[end] == "[" { inClass = true } else if characters[end] == "]" { inClass = false } else if characters[end] == "/", !inClass { break }
                    end += 1
                }
                out.append("/"); blank((index + 1)..<min(end, characters.count))
                if end < characters.count { out.append("/") }
                previous = "/"; index = end + 1; continue
            }
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
