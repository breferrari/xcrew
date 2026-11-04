import Foundation

/// The disk, as it is.
public struct LocalFiles: FileReading {
    public init() {}

    public func data(at url: URL) -> Data? { try? Data(contentsOf: url) }

    public func names(in folder: URL) -> [String]? { try? FileManager.default.contentsOfDirectory(atPath: folder.path) }

    public func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}
