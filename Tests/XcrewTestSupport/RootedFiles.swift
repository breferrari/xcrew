import Foundation
import Testing
import XcrewCore

/// The disk as a test may read it: below its own folders, the test bed, and the folders a result bundle's attachments are
/// exported to, `xcrew-attachments-…`. A read anywhere else records an issue, failing the test, and reads nothing: a test
/// never reads the real Mac. A folder it's given that a test didn't make, one outside the temporary folder or the test
/// bed, as `/Applications` or a made-up home, is none of its own. Paths are
/// compared resolved, as `/var` and `/private/var` are one folder.
public struct RootedFiles: FileReading {
    let roots: [String]
    let disk = LocalFiles()

    public init(roots: [URL]) {
        let bed = Testbed.isCheckedOut ? [Self.resolved(Testbed.root)] : []
        let temporary = Self.resolved(FileManager.default.temporaryDirectory) + "/"
        self.roots = bed + [temporary + "xcrew-attachments-"] + roots.map(Self.resolved).filter { $0.hasPrefix(temporary) || bed.contains(where: $0.hasPrefix) }
    }

    static func resolved(_ url: URL) -> String {
        let path = URL(fileURLWithPath: url.path).resolvingSymlinksInPath().path
        return path.hasPrefix("/private/var/") || path.hasPrefix("/private/tmp/") ? String(path.dropFirst("/private".count)) : path
    }

    /// Whether a test may read `url`, recording an issue when it may not.
    func allows(_ url: URL, sourceLocation: SourceLocation = #_sourceLocation) -> Bool {
        let path = Self.resolved(url)
        guard roots.contains(where: { path == $0 || path.hasPrefix($0.hasSuffix("-") ? $0 : $0 + "/") }) else {
            Issue.record("a test read \(url.path), outside its own folders: it would read this Mac", sourceLocation: sourceLocation)
            return false
        }
        return true
    }

    public func data(at url: URL) -> Data? { allows(url) ? disk.data(at: url) : nil }

    public func names(in folder: URL) -> [String]? { allows(folder) ? disk.names(in: folder) : nil }

    public func exists(_ url: URL) -> Bool { allows(url) && disk.exists(url) }
}
