import Foundation

/// One `import` declaration in a Swift file: the module it names, the line it's on, and whether it sits inside `#if`.
public struct SwiftImport: Sendable, Equatable, Codable {
    public let module: String
    public let line: Int
    /// Inside `#if`: whether it's compiled depends on the condition, which the reading doesn't evaluate.
    public let isConditional: Bool

    public init(module: String, line: Int, isConditional: Bool = false) {
        (self.module, self.line, self.isConditional) = (module, line, isConditional)
    }

    /// The imports in a Swift file's text, by The Swift Programming Language's grammar (`attributes? import
    /// import-kind? import-path`) and SE-0409's access level before `import`. An import's module is its path's first
    /// component. Comments and string literals are skipped.
    public static func all(in source: String) -> [SwiftImport] {
        var imports: [SwiftImport] = []
        var conditions = 0
        let declaration = declaration
        // "\r\n" is one Character, which splitting on "\n" wouldn't break.
        for (index, line) in code(of: source.replacing("\r\n", with: "\n")).split(separator: "\n", omittingEmptySubsequences: false).enumerated() where line.contains("#") || line.contains("import") {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("#if") { conditions += 1 } else if text.hasPrefix("#endif") { conditions = max(0, conditions - 1) }
            if let match = text.prefixMatch(of: declaration) {
                imports.append(SwiftImport(module: String(match.1), line: index + 1, isConditional: conditions > 0))
            }
        }
        return imports
    }

    /// An import declaration at the start of a line: its module is the first capture.
    static var declaration: Regex<(Substring, Substring)> {
        /(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s+)*(?:(?:public|package|internal|fileprivate|private|open)\s+)?import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?([A-Za-z_][A-Za-z0-9_]*)/
    }

    /// Where the scan is: in code, possibly an interpolation inside a string, or in a string literal, with the
    /// delimiter that closes it and the escape its `#`s make.
    private enum Mode {
        case code(parentheses: Int, isInterpolation: Bool)
        case string(closing: [Unicode.Scalar], escape: [Unicode.Scalar])
    }

    /// The source with every comment and string literal blanked to spaces, its lines kept where they were.
    static func code(of source: String) -> String {
        let scalars = Array(source.unicodeScalars)
        var kept = String.UnicodeScalarView()
        var modes: [Mode] = [.code(parentheses: 0, isInterpolation: false)]
        var index = 0
        func starts(_ wanted: [Unicode.Scalar], at position: Int) -> Bool {
            guard position + wanted.count <= scalars.count else { return false }
            return wanted.indices.allSatisfy { scalars[position + $0] == wanted[$0] }
        }
        let lineComment: [Unicode.Scalar] = ["/", "/"], opening: [Unicode.Scalar] = ["/", "*"], closing: [Unicode.Scalar] = ["*", "/"]
        let quote: [Unicode.Scalar] = ["\""], quotes: [Unicode.Scalar] = ["\"", "\"", "\""]
        func blank(_ count: Int) {
            for offset in 0..<count where index + offset < scalars.count { kept.append(scalars[index + offset] == "\n" ? "\n" : " ") }
            index += count
        }
        while index < scalars.count {
            switch modes[modes.count - 1] {
            case let .code(parentheses, isInterpolation):
                if starts(lineComment, at: index) {
                    while index < scalars.count, scalars[index] != "\n" { blank(1) }
                } else if starts(opening, at: index) {
                    var depth = 0
                    repeat {
                        if starts(opening, at: index) { depth += 1; blank(2) } else if starts(closing, at: index) { depth -= 1; blank(2) } else { blank(1) }
                    } while depth > 0 && index < scalars.count
                } else if scalars[index] == "#" || scalars[index] == "\"" {
                    var hashes = 0
                    while index + hashes < scalars.count, scalars[index + hashes] == "#" { hashes += 1 }
                    let marks = [Unicode.Scalar](repeating: "#", count: hashes)
                    if starts(quotes, at: index + hashes) {
                        blank(hashes + 3)
                        modes.append(.string(closing: quotes + marks, escape: ["\\"] + marks))
                    } else if starts(quote, at: index + hashes) {
                        blank(hashes + 1)
                        modes.append(.string(closing: quote + marks, escape: ["\\"] + marks))
                    } else {
                        kept.append(scalars[index])
                        index += 1
                    }
                } else if scalars[index] == "(" {
                    modes[modes.count - 1] = .code(parentheses: parentheses + 1, isInterpolation: isInterpolation)
                    kept.append(scalars[index])
                    index += 1
                } else if scalars[index] == ")" {
                    if parentheses == 0 && isInterpolation {
                        modes.removeLast()
                        blank(1)
                    } else {
                        modes[modes.count - 1] = .code(parentheses: max(0, parentheses - 1), isInterpolation: isInterpolation)
                        kept.append(scalars[index])
                        index += 1
                    }
                } else {
                    kept.append(scalars[index])
                    index += 1
                }
            case let .string(closing, escape):
                if starts(escape, at: index), index + escape.count < scalars.count, scalars[index + escape.count] == "(" {
                    blank(escape.count + 1)
                    modes.append(.code(parentheses: 0, isInterpolation: true))
                } else if starts(escape, at: index) {
                    blank(escape.count + 1)
                } else if starts(closing, at: index) {
                    blank(closing.count)
                    modes.removeLast()
                } else {
                    blank(1)
                }
            }
        }
        return String(kept)
    }
}
