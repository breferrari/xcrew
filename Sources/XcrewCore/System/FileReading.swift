import Foundation

/// How xcrew reads the machine's own files: its Xcodes, simulators and caches. `Machine.live` reads the disk; a test's
/// Machine reads only the folders it made, so a test never reads the real Mac.
public protocol FileReading: Sendable {
    /// The file's bytes; nil when it can't be read.
    func data(at url: URL) -> Data?
    /// The names in a folder, in no order; nil when it isn't one or can't be read.
    func names(in folder: URL) -> [String]?
    /// Whether anything is there.
    func exists(_ url: URL) -> Bool
}

extension FileReading {
    /// The file as UTF-8 text; nil when it can't be read.
    public func text(at url: URL) -> String? {
        data(at: url).map { String(decoding: $0, as: UTF8.self) }
    }
}

/// The disk, as it is.
public struct LocalFiles: FileReading {
    public init() {}

    public func data(at url: URL) -> Data? { try? Data(contentsOf: url) }

    public func names(in folder: URL) -> [String]? { try? FileManager.default.contentsOfDirectory(atPath: folder.path) }

    public func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}
