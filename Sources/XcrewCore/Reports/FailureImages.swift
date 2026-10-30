import Foundation

/// A failed test's images, kept where Claude can Read them: the paths, in the order the notes list them, and their folder.
public struct FailureImages: Sendable, Equatable {
    public let paths: [String]
    public let folder: String

    /// Images listed for a test; the rest are counted, with their folder.
    static let mostShown = 3

    /// The images listed by path.
    var shown: [String] { Array(paths.prefix(Self.mostShown)) }

    /// `and 2 more images in <folder>`, for the images past those listed; nil when there are none.
    var more: String? {
        let count = paths.count - Self.mostShown
        guard count > 0 else { return nil }
        return "and \(count) more \(count == 1 ? "image" : "images") in \(folder)"
    }

    /// Image formats Claude's Read shows, by extension.
    static let extensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff", "webp"]

    /// The format a file's first bytes say it is, as its extension; nil when they say none of the image formats.
    static func format(of data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        func starts(_ prefix: [UInt8], at offset: Int = 0) -> Bool {
            bytes.count >= offset + prefix.count && Array(bytes[offset..<offset + prefix.count]) == prefix
        }
        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "png" }
        if starts([0xFF, 0xD8, 0xFF]) { return "jpg" }
        if starts(Array("GIF8".utf8)) { return "gif" }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return "tiff" }
        if starts(Array("RIFF".utf8)), starts(Array("WEBP".utf8), at: 8) { return "webp" }
        if starts(Array("ftyp".utf8), at: 4), ["heic", "heix", "mif1", "msf1"].contains(where: { starts(Array($0.utf8), at: 8) }) { return "heic" }
        return nil
    }

    /// The name an attachment is kept under when it's an image: its suggested name, with the extension its content says
    /// when the name has none of an image's. Nil when neither its name nor its content says image. The exported file's
    /// own extension says nothing: xcresulttool leaves some images without one.
    static func keptName(suggested: String, content: URL) -> String? {
        let name = suggested.replacingOccurrences(of: "/", with: "-")
        if extensions.contains(URL(fileURLWithPath: name).pathExtension.lowercased()) { return name }
        let head = (try? FileHandle(forReadingFrom: content)).flatMap { handle in
            defer { try? handle.close() }
            return try? handle.read(upToCount: 12)
        }
        return head.flatMap(format(of:)).map { "\(name).\($0)" }
    }

    /// Where an image sorts: a snapshot's reference, then its failing render, then their difference, by the words both
    /// libraries begin their names with (`reference`, `Reference Image`; `failure`, `Failed Image`; `difference`,
    /// `Diffed Image`), then the rest.
    static func rank(_ name: String) -> Int {
        let lowered = name.lowercased()
        return ["ref", "fail", "diff"].firstIndex { lowered.hasPrefix($0) } ?? 3
    }
}
