import Foundation

/// A binary property list (`bplist00`), read the way MobileBuildMCP's `bplist-parser` reads Xcode's `xcuserstate`: its
/// keyed-archive references (UIDs) kept as values, which neither `PropertyListDecoder` nor a safe
/// `PropertyListSerialization` call gives. Strings, integers, UIDs, arrays and dictionaries are read; any other object is
/// `other`. Every offset is checked, so a damaged file reads as nothing rather than failing.
public enum BinaryPropertyList: Sendable, Equatable {
    case string(String)
    case integer(Int)
    case uid(Int)
    case array([BinaryPropertyList])
    case dictionary([String: BinaryPropertyList])
    case other

    /// The top object of `data`; nil when it isn't a binary property list or can't be read.
    public static func read(_ data: Data) -> BinaryPropertyList? {
        let bytes = [UInt8](data)
        guard bytes.count >= 40, bytes.starts(with: Array("bplist00".utf8)) else { return nil }
        let trailer = bytes.count - 32
        let offsetSize = Int(bytes[trailer + 6]), referenceSize = Int(bytes[trailer + 7])
        guard let count = number(bytes, at: trailer + 8, size: 8), let top = number(bytes, at: trailer + 16, size: 8),
              let table = number(bytes, at: trailer + 24, size: 8), (1...8).contains(offsetSize), (1...8).contains(referenceSize),
              count > 0, top < count, table <= trailer, count <= (trailer - table) / offsetSize else { return nil }
        let reader = Reader(bytes: bytes, offsetSize: offsetSize, referenceSize: referenceSize, count: count, table: table)
        return reader.object(top, depth: 0)
    }

    /// A big-endian unsigned number of `size` bytes at `offset`; nil past the end or beyond `Int`.
    static func number(_ bytes: [UInt8], at offset: Int, size: Int) -> Int? {
        guard offset >= 0, size > 0, size <= 8, offset + size <= bytes.count else { return nil }
        let value = bytes[offset..<(offset + size)].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return value <= UInt64(Int.max) ? Int(value) : nil
    }

    private final class Reader {
        let bytes: [UInt8]
        let offsetSize: Int
        let referenceSize: Int
        let count: Int
        let table: Int
        /// Objects left to read: an object shared by many reads once per reference, so a file whose references fan out
        /// ends here. Xcode's state holds a few thousand.
        var budget: Int

        /// Nesting deeper than any keyed archive's, so a list that refers to itself ends.
        static let deepest = 64

        init(bytes: [UInt8], offsetSize: Int, referenceSize: Int, count: Int, table: Int) {
            (self.bytes, self.offsetSize, self.referenceSize, self.count, self.table) = (bytes, offsetSize, referenceSize, count, table)
            budget = max(count * 4, 1_000)
        }

        func object(_ index: Int, depth: Int) -> BinaryPropertyList? {
            budget -= 1
            guard budget >= 0, index >= 0, index < count, depth < Self.deepest,
                  let start = number(bytes, at: table + index * offsetSize, size: offsetSize), start < bytes.count else { return nil }
            let marker = bytes[start], low = Int(marker & 0x0F)
            switch marker >> 4 {
            case 0x1:
                // A 16-byte integer is beyond `Int`, and nothing a selection needs.
                return number(bytes, at: start + 1, size: 1 << low).map(BinaryPropertyList.integer) ?? .other
            case 0x5:
                guard let (length, at) = length(low, after: start), length <= bytes.count - at else { return nil }
                return String(bytes: bytes[at..<(at + length)], encoding: .ascii).map(BinaryPropertyList.string)
            case 0x6:
                guard let (length, at) = length(low, after: start), length <= (bytes.count - at) / 2 else { return nil }
                return String(bytes: bytes[at..<(at + length * 2)], encoding: .utf16BigEndian).map(BinaryPropertyList.string)
            case 0x8:
                return number(bytes, at: start + 1, size: low + 1).map(BinaryPropertyList.uid)
            case 0xA:
                guard let (length, at) = length(low, after: start), length <= (bytes.count - at) / referenceSize else { return nil }
                var items: [BinaryPropertyList] = []
                for position in 0..<length {
                    guard let reference = number(bytes, at: at + position * referenceSize, size: referenceSize),
                          let item = object(reference, depth: depth + 1) else { return nil }
                    items.append(item)
                }
                return .array(items)
            case 0xD:
                guard let (length, at) = length(low, after: start), length <= (bytes.count - at) / (2 * referenceSize) else { return nil }
                var dictionary: [String: BinaryPropertyList] = [:]
                for position in 0..<length {
                    guard let keyReference = number(bytes, at: at + position * referenceSize, size: referenceSize),
                          let valueReference = number(bytes, at: at + (length + position) * referenceSize, size: referenceSize),
                          case let .string(key)? = object(keyReference, depth: depth + 1),
                          let value = object(valueReference, depth: depth + 1) else { return nil }
                    dictionary[key] = value
                }
                return .dictionary(dictionary)
            default:
                return .other
            }
        }

        /// An object's length and where its contents start: the marker's low nibble, or with `0xF` the integer after it.
        func length(_ low: Int, after start: Int) -> (Int, Int)? {
            guard low == 0x0F else { return (low, start + 1) }
            guard start + 1 < bytes.count, bytes[start + 1] >> 4 == 0x1 else { return nil }
            let size = 1 << Int(bytes[start + 1] & 0x0F)
            guard let length = number(bytes, at: start + 2, size: size), length <= bytes.count else { return nil }
            return (length, start + 2 + size)
        }
    }
}
