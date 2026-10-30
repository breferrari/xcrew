import Foundation

/// A property list's value, read through `PropertyListDecoder`, whose API is safe where `PropertyListSerialization`
/// takes a pointer. A project file holds strings, arrays and dictionaries; anything else reads as nothing.
enum PlistValue: Decodable, Sendable {
    case string(String)
    case array([PlistValue])
    case dictionary([String: PlistValue])
    case other

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([PlistValue].self) {
            self = .array(array)
        } else if let dictionary = try? container.decode([String: PlistValue].self) {
            self = .dictionary(dictionary)
        } else {
            self = .other
        }
    }

    /// The value as Foundation's property list types: `String`, `[Any]` and `[String: Any]`.
    var foundation: Any {
        switch self {
        case let .string(string): string
        case let .array(array): array.map(\.foundation)
        case let .dictionary(dictionary): dictionary.mapValues(\.foundation)
        case .other: NSNull()
        }
    }
}
