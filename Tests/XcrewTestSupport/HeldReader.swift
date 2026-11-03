import Foundation
import Testing
import XcrewCore

/// A shell command that leaves a marker, then blocks opening a FIFO no one writes until a signal ends it: a stand-in for
/// a program that runs on, which no clock ends, however slow the machine. Its FIFO's path, in its command line, finds it
/// with `pgrep -f`; the marker says the command itself has started, not only a shell that would start it.
public struct HeldReader: Sendable {
    public let path: String

    /// A new FIFO for it, made by `mkfifo`; a test that can't have one fails here rather than waiting on nothing.
    public static func make(sourceLocation: SourceLocation = #_sourceLocation) async throws -> HeldReader {
        let path = FileManager.default.temporaryDirectory.appending(path: "xcrew-held-\(UUID().uuidString)").path
        let made = await SystemCommandRunner(path: "/usr/bin:/bin").run("/usr/bin/mkfifo", path)
        try #require(made.succeeded, "mkfifo \(path): \(made.stderr)", sourceLocation: sourceLocation)
        return HeldReader(path: path)
    }

    /// The command, for `sh -c`.
    public var command: String { ": > '\(marker)'; read -r _ < '\(path)'" }

    /// The file the command leaves once it has started.
    public var marker: String { path + ".started" }

    /// Whether the command has started.
    public var hasStarted: Bool { FileManager.default.fileExists(atPath: marker) }

    /// Removes the FIFO and the marker.
    public func remove() {
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.removeItem(atPath: marker)
    }
}
