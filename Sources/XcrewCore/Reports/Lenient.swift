import Foundation

/// A field read as nil when it's missing or of another type, so one odd field doesn't lose the rest:
/// a server update degrades what's read from its output rather than breaking it.
@propertyWrapper
struct Lenient<Value: Decodable & Sendable>: Decodable, Sendable {
    var wrappedValue: Value?

    init(wrappedValue: Value? = nil) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: any Decoder) throws {
        wrappedValue = try? decoder.singleValueContainer().decode(Value.self)
    }
}

extension KeyedDecodingContainer {
    /// Missing reads as nil; `null` goes to the value, which may read it (`JSONText` does).
    func decode<Value>(_: Lenient<Value>.Type, forKey key: Key) throws -> Lenient<Value> {
        guard contains(key), let decoder = try? superDecoder(forKey: key) else { return Lenient() }
        return try Lenient(from: decoder)
    }
}
