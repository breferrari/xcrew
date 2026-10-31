import Foundation

/// The targets that build one file, as the workspace's projects list it.
public struct FileOwners: Sendable, Equatable, Codable {
    /// The file's path from the root.
    public let file: String
    public var targets: [String] = []
    /// An exception set changes its membership, which the reading doesn't model; absent when none does.
    public var excepted: Bool?
    /// Why the workspace couldn't be read; nothing else is said then.
    public var unread: String?

    /// `file` is a path from the root, or an absolute one.
    public static func of(_ file: String, in project: Project) -> FileOwners {
        let url = file.hasPrefix("/") ? URL(fileURLWithPath: file) : project.root.appending(path: file)
        let path = ProjectLayout.canonicalCreating(url)
        var owners = FileOwners(file: ProjectLayout.path(path, from: ProjectLayout.canonical(project.root)))
        switch WorkspaceGraph.read(project) {
        case let .failure(unread):
            owners.unread = unread.reason
        case let .success(workspace):
            let owned = workspace.builders(of: path)
            owners.targets = owned.targets.sorted()
            owners.excepted = owned.isExcepted ? true : nil
        }
        return owners
    }
}
