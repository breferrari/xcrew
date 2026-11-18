import Foundation

/// The repository's common git folder, which every checkout of it shares: where xcrew keeps what holds for all of them.
public enum GitCommonFolder {
    /// The file at `path` in the common git folder of the repository `folder` is in; nil outside git.
    public static func file(_ path: String, for folder: URL, using runner: any CommandRunning) async -> URL? {
        let ran = await runner.run("git", "-C", folder.path, "rev-parse", "--path-format=absolute", "--git-common-dir")
        let common = ran.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ran.succeeded, !common.isEmpty else { return nil }
        return URL(fileURLWithPath: common).appending(path: path)
    }
}
