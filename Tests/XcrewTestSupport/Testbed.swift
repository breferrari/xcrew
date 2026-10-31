import Foundation

/// Where the test bed is checked out: `XCREW_TESTBED`, else a clone beside this repository's.
public enum Testbed {
    public static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    public static let root = ProcessInfo.processInfo.environment["XCREW_TESTBED"].map { URL(fileURLWithPath: $0) }
        ?? repository.deletingLastPathComponent().appending(path: "xcrew-testbed")
    public static var isCheckedOut: Bool { FileManager.default.fileExists(atPath: root.appending(path: "forms").path) }
}
