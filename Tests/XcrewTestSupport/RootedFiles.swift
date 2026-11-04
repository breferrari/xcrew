import Foundation
import Testing
import XcrewCore

/// The disk as a test may read it: below its own folders, the test bed, and the temporary folders xcrew's tests make,
/// `xcrew-…`. A read anywhere else records an issue, failing the test, and reads nothing: a test never reads the real Mac.
/// A folder it's given that a test didn't make, as `/Applications` or a made-up home, is none of its own. Paths are
/// compared resolved, as `/var` and `/private/var` are one folder.
public struct RootedFiles: FileReading {
    let roots: [String]
    let disk = LocalFiles()

    public init(roots: [URL]) {
        let bed = Testbed.isCheckedOut ? [Self.resolved(Testbed.root)] : []
        self.roots = bed + roots.map(Self.resolved).filter { Self.isMade($0) || bed.contains(where: $0.hasPrefix) }
    }

    /// Whether `path`, resolved, is in a temporary folder xcrew's tests make.
    static func isMade(_ path: String) -> Bool {
        let temporary = resolved(FileManager.default.temporaryDirectory)
        return path.hasPrefix(temporary + "/") && path.dropFirst(temporary.count + 1).hasPrefix("xcrew-")
    }

    static func resolved(_ url: URL) -> String {
        let path = URL(fileURLWithPath: url.path).resolvingSymlinksInPath().path
        return path.hasPrefix("/private/var/") || path.hasPrefix("/private/tmp/") ? String(path.dropFirst("/private".count)) : path
    }

    /// Whether a test may read `url`, recording an issue when it may not.
    func allows(_ url: URL, sourceLocation: SourceLocation = #_sourceLocation) -> Bool {
        let path = Self.resolved(url)
        guard Self.isMade(path) || roots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else {
            Issue.record("a test read \(url.path), outside its own folders: it would read this Mac", sourceLocation: sourceLocation)
            return false
        }
        return true
    }

    public func data(at url: URL) -> Data? { allows(url) ? disk.data(at: url) : nil }

    public func names(in folder: URL) -> [String]? { allows(folder) ? disk.names(in: folder) : nil }

    public func exists(_ url: URL) -> Bool { allows(url) && disk.exists(url) }
}
