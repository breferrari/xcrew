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
    /// Whether nothing is there, as opposed to a folder that can't be looked at.
    func isMissing(_ url: URL) -> Bool
    /// When the file was last changed; nil when it can't be read.
    func modified(_ url: URL) -> Date?
    /// The path with every symbolic link in it followed, as the disk has them.
    func resolved(_ url: URL) -> URL
    /// The paths of the volumes mounted now.
    func mountedVolumes() -> Set<String>
    /// Takes up the Machine it reads for, as it's made: a test's checks the folders the Machine names are its own.
    func admit(_ machine: Machine)
}

extension FileReading {
    /// The file as UTF-8 text; nil when it can't be read.
    public func text(at url: URL) -> String? {
        data(at: url).flatMap { String(data: $0, encoding: .utf8) }
    }
}
