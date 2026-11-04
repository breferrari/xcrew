import Foundation
import Testing
import XcrewCore

/// The disk as a test may read it: below its own folders, the test bed, this package's checkout, whose plugin files the
/// hooks read, and `/nonexistent`, where `FakeRunner` puts a tool it makes up, on no Mac. A read anywhere else records an
/// issue, failing the test, and reads nothing: a test never reads the real Mac. A folder it's given that a test didn't make, one outside the temporary folder or the test
/// bed, as `/Applications` or a made-up home, is none of its own. Paths are
/// compared resolved, as `/var` and `/private/var` are one folder.
public struct RootedFiles: FileReading {
    let roots: [String]
    let disk = LocalFiles()

    public init(roots: [URL]) {
        let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bed = (Testbed.isCheckedOut ? [Self.resolved(Testbed.root)] : []) + [Self.resolved(checkout), "/nonexistent"]
        let temporary = Self.resolved(FileManager.default.temporaryDirectory) + "/"
        self.roots = bed + roots.map(Self.resolved).filter { $0.hasPrefix(temporary) || bed.contains(where: $0.hasPrefix) }
    }

    static func resolved(_ url: URL) -> String {
        let path = URL(fileURLWithPath: url.path).resolvingSymlinksInPath().path
        return path.hasPrefix("/private/var/") || path.hasPrefix("/private/tmp/") ? String(path.dropFirst("/private".count)) : path
    }

    /// Whether a test may read `url`, recording an issue when it may not.
    func allows(_ url: URL, sourceLocation: SourceLocation = #_sourceLocation) -> Bool {
        let path = Self.resolved(url)
        guard roots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else {
            Issue.record("a test read \(url.path), outside its own folders: it would read this Mac", sourceLocation: sourceLocation)
            return false
        }
        return true
    }

    public func data(at url: URL) -> Data? { allows(url) ? disk.data(at: url) : nil }

    public func names(in folder: URL) -> [String]? { allows(folder) ? disk.names(in: folder) : nil }

    public func exists(_ url: URL) -> Bool { allows(url) && disk.exists(url) }

    public func isMissing(_ url: URL) -> Bool { allows(url) && disk.isMissing(url) }

    public func modified(_ url: URL) -> Date? { allows(url) ? disk.modified(url) : nil }

    /// Fails the test when the Machine's home is the Mac's own, or its cache is in the Mac's own caches: what those hold is
    /// read directly, so they must be folders the test made.
    public func admit(_ machine: Machine) {
        let mine = Self.resolved(FileManager.default.homeDirectoryForCurrentUser)
        let caches = mine + "/Library/Caches"
        let (home, cache) = (Self.resolved(machine.home), Self.resolved(machine.cacheFolder))
        if home == mine {
            Issue.record("a test's Machine has the Mac's own home, \(machine.home.path)")
        }
        if cache == caches || cache.hasPrefix(caches + "/") {
            Issue.record("a test's Machine keeps its cache in the Mac's own caches, \(machine.cacheFolder.path)")
        }
    }
}
