import Foundation

/// Any JSON value, written as text the way Swift wrote the value `JSONSerialization` gave it: text as
/// it is, a number as `NSNumber` writes it, `true` and `false` as `1` and `0`, `null` as `<null>`.
/// Objects and arrays are written key by key, sorted, so a message inside one can still be read.
struct JSONText: Decodable, Sendable {
    let text: String

    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            text = "<null>"
        } else if let string = try? value.decode(String.self) {
            text = string
        } else if let bool = try? value.decode(Bool.self) {
            text = bool ? "1" : "0"
        } else if let number = try? value.decode(Double.self) {
            text = NSNumber(value: number).description
        } else if let object = try? value.decode([String: JSONText].self) {
            text = "{" + object.sorted { $0.key < $1.key }.map { "\($0.key) = \($0.value.text)" }.joined(separator: "; ") + "}"
        } else {
            text = "(" + (try value.decode([JSONText].self)).map(\.text).joined(separator: ", ") + ")"
        }
    }
}
