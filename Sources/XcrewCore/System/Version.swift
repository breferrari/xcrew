import Foundation

/// A dotted version number, compared part by part; missing parts count as zero. Each part is its first run of digits:
/// `v2` is 2, and a beta's `2b3` is 2.
struct Version: Comparable, CustomStringConvertible {
    let parts: [Int]

    init(_ text: String) {
        parts = text.split(separator: ".").map { part in Int(part.drop { !$0.isNumber }.prefix { $0.isNumber }) ?? 0 }
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    /// The first number, as the text gave it: nil when the text starts with none, so an unknown version isn't 0.
    static func major(of text: String) -> Int? { Int(text.drop { !$0.isNumber }.prefix { $0.isNumber }) }

    static func < (lhs: Version, rhs: Version) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        let left = lhs.parts + Array(repeating: 0, count: count - lhs.parts.count)
        let right = rhs.parts + Array(repeating: 0, count: count - rhs.parts.count)
        return left.lexicographicallyPrecedes(right)
    }

    static func == (lhs: Version, rhs: Version) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}
