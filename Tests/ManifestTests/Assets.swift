import Foundation

/// Where xcrew-assets, the repository the README's images live in, is checked out: `XCREW_ASSETS`, else a clone beside
/// this repository's. CI checks it out at the commit the README pins.
enum Assets {
    static let root = ProcessInfo.processInfo.environment["XCREW_ASSETS"].map { URL(fileURLWithPath: $0) }
        ?? ManifestTests.repository.deletingLastPathComponent().appending(path: "xcrew-assets")
    static var isCheckedOut: Bool { FileManager.default.fileExists(atPath: root.appending(path: "mockups.py").path) }

    static func text(_ file: String) throws -> String {
        try String(contentsOf: root.appending(path: file), encoding: .utf8)
    }
}
