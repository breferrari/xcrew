import Foundation

/// Whether xcrew drops MobileBuildMCP's finished test-run bundles (`FinishedTestBundles`): deleting them is the person's
/// to agree to, so it's off until setup records `drop`. Kept in the repository's common git folder, beside
/// `WorktreeSimulatorRecord`, so every checkout of it reads the same choice.
public enum FinishedTestBundlesChoice: String, Sendable, Codable {
    case keep, drop

    /// The choice can't be recorded outside a git repository.
    public struct NotInGit: LocalizedError {
        public var errorDescription: String? { "the choice of what to do with finished test bundles is kept in the repository's git folder, and this project isn't in git" }
    }

    /// Where the choice sits in the repository's common git folder.
    static let path = "xcrew/finished-test-bundles"

    /// The choice's file for the repository the project is in; nil outside git.
    static func file(for project: Project, using runner: any CommandRunning) async -> URL? {
        await GitCommonFolder.file(path, for: project.root, using: runner)
    }

    /// The recorded choice, `keep` when none is; nil outside git, where none can be.
    public static func read(for project: Project, using runner: any CommandRunning) async -> FinishedTestBundlesChoice? {
        guard let file = await file(for: project, using: runner) else { return nil }
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        return FinishedTestBundlesChoice(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .keep
    }

    /// Records this choice for every checkout of the project's repository.
    public func write(for project: Project, using runner: any CommandRunning) async throws {
        guard let file = await Self.file(for: project, using: runner) else { throw NotInGit() }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("\(rawValue)\n".utf8).write(to: file, options: .atomic)
    }
}
