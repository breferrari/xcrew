import Foundation

/// An error a failed build reported, from a server's result or a build log: what it says, the lines under it, and the
/// file and line it names, when it names one.
public struct ReportedError: Sendable, Equatable {
    public let message: String
    /// The lines that go on from the message, such as a destination specifier.
    public let detail: [String]
    /// The file it points at, as the tool wrote it: an absolute path, or a name such as `<unknown>`.
    public let path: String?
    public let line: Int?

    public init(message: String, detail: [String] = [], path: String? = nil, line: Int? = nil) {
        self.message = message
        self.detail = detail
        self.path = path
        self.line = line
    }

    /// Whether it points at a file under `root`, a resolved path, where the code put it.
    func isInside(root: String) -> Bool {
        guard let path, path.hasPrefix("/") else { return false }
        return ProjectLayout.canonical(URL(fileURLWithPath: path)).hasPrefix(root + "/")
    }
}
