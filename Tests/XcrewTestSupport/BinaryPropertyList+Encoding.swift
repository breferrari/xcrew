import Foundation
import XcrewCore

extension BinaryPropertyList {
    /// This value as a `bplist00` file, each value its own object: what Xcode writes, for the reader's tests. ASCII
    /// strings only.
    public var encoded: Data {
        var objects: [[UInt8]] = []
        func add(_ value: BinaryPropertyList) -> Int {
            let index = objects.count
            objects.append([])
            objects[index] = encode(value)
            return index
        }
        func header(_ kind: UInt8, _ length: Int) -> [UInt8] {
            length < 15 ? [kind << 4 | UInt8(length)] : [kind << 4 | 0x0F, 0x11, UInt8(length >> 8), UInt8(length & 0xFF)]
        }
        func bigEndian(_ number: Int, bytes: Int) -> [UInt8] { (0..<bytes).reversed().map { UInt8(truncatingIfNeeded: number >> ($0 * 8)) } }
        func reference(_ index: Int) -> [UInt8] { bigEndian(index, bytes: 2) }
        func encode(_ value: BinaryPropertyList) -> [UInt8] {
            switch value {
            case let .string(string): return header(0x5, string.utf8.count) + Array(string.utf8)
            case let .integer(number): return [0x13] + bigEndian(number, bytes: 8)
            case let .uid(index): return [0x81] + bigEndian(index, bytes: 2)
            case let .array(items): return header(0xA, items.count) + items.map(add).flatMap(reference)
            case let .dictionary(dictionary):
                let keys = dictionary.keys.sorted()
                return header(0xD, keys.count) + keys.map { add(.string($0)) }.flatMap(reference) + keys.compactMap { dictionary[$0] }.map(add).flatMap(reference)
            case .other: return [0x00]
            }
        }
        _ = add(self)
        var bytes = Array("bplist00".utf8)
        var offsets: [Int] = []
        for object in objects {
            offsets.append(bytes.count)
            bytes += object
        }
        let table = bytes.count
        for offset in offsets { bytes += bigEndian(offset, bytes: 4) }
        bytes += [0, 0, 0, 0, 0, 0, 4, 2] + bigEndian(objects.count, bytes: 8) + bigEndian(0, bytes: 8) + bigEndian(table, bytes: 8)
        return Data(bytes)
    }
}
