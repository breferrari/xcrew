import Foundation

/// The simulators `setup --worktree` made, each by its id and the worktree it was made for, kept in the repository's
/// common git folder so every checkout reads the same one. The doctor names a simulator to delete only from here, never
/// by its name alone, which two clones of one folder name share.
public struct WorktreeSimulatorRecord: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let udid: String
        /// The worktree's top folder, canonical (`ProjectLayout.canonical`), as `git worktree list` names it.
        public let worktree: String
    }

    public var entries: [Entry] = []

    /// Where the record sits in the repository's common git folder.
    static let path = "xcrew/worktree-simulators"

    /// The record's file for the repository `folder` is in; nil outside git.
    public static func file(for folder: URL, using runner: any CommandRunning) async -> URL? {
        let ran = await runner.run("git", "-C", folder.path, "rev-parse", "--path-format=absolute", "--git-common-dir")
        let common = ran.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ran.succeeded, !common.isEmpty else { return nil }
        return URL(fileURLWithPath: common).appending(path: path)
    }

    /// The record in `file`: one `udid<TAB>path` per line; none when it isn't there or can't be read.
    public static func read(_ file: URL) -> WorktreeSimulatorRecord {
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        return WorktreeSimulatorRecord(entries: text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", maxSplits: 1)
            return fields.count == 2 ? Entry(udid: String(fields[0]), worktree: String(fields[1])) : nil
        })
    }

    /// This record with `udid` made for `worktree`, in place of what it said of that id.
    public func adding(_ udid: String, for worktree: URL) -> WorktreeSimulatorRecord {
        WorktreeSimulatorRecord(entries: entries.filter { $0.udid != udid } + [Entry(udid: udid, worktree: ProjectLayout.canonical(worktree))])
    }

    /// Writes the record whole or not at all.
    public func write(to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(entries.map { "\($0.udid)\t\($0.worktree)\n" }.joined().utf8).write(to: file, options: .atomic)
    }
}
