import Foundation

/// The disk, as it is.
public struct LocalFiles: FileReading {
    public init() {}

    public func data(at url: URL) -> Data? { try? Data(contentsOf: url) }

    public func names(in folder: URL) -> [String]? { try? FileManager.default.contentsOfDirectory(atPath: folder.path) }

    public func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    public func isMissing(_ url: URL) -> Bool {
        do {
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
            return false
        } catch {
            return (error as? CocoaError)?.code == .fileReadNoSuchFile
        }
    }

    public func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// The live disk reads for any Machine.
    public func admit(_ machine: Machine) {}
}
