import Foundation

/// The MobileBuildMCP runs going in the project's other checkouts, its other worktrees, read from the logs MobileBuildMCP
/// writes as a run goes: each one's newest build or test log that has no verdict yet and was written lately.
public enum OtherRuns {
    public struct Run: Sendable, Equatable, Codable {
        /// The checkout's folder name, as the person knows the worktree.
        public let worktree: String
        public let root: String
        /// The tool that writes the log, from its name: `test_sim`.
        public let tool: String
        public let phase: String?
    }

    /// How long a log may go unwritten and its run still count as going: xcodebuild is quiet through a link, a long test
    /// or a simulator's boot. The mod clears what it shows after as long.
    public static let quietFor: TimeInterval = 90

    /// The runs going now in the project's checkouts but this one; none outside git, and none from a checkout whose folder
    /// is gone or whose workspace can't be read.
    public static func going(project: Project, machine: Machine, now: Date) async -> [Run] {
        let here = ProjectLayout.canonical(project.root)
        let others = Dictionary(grouping: await ProjectWorkspaces.live(of: project, using: machine.runner)) { $0.root }
            .filter { root, _ in ProjectLayout.canonicalPath(root) != here && FileManager.default.fileExists(atPath: root) }
        let workspaces = machine.home.appending(path: "Library/Developer/MobileBuildMCP/workspaces")
        return others.compactMap { root, checkouts -> Run? in
            let newest = checkouts.compactMap { newestLog(in: workspaces.appending(path: $0.key).appending(path: "logs")) }.max { $0.modified < $1.modified }
            guard let newest, now.timeIntervalSince(newest.modified) <= quietFor else { return nil }
            let kind: Report.Kind = newest.tool.hasPrefix("test") ? .test : .build
            guard RunLog.outcome(of: RunLog.end(ofLogAt: newest.url.path), kind: kind) == nil else { return nil }
            return Run(worktree: URL(fileURLWithPath: root).lastPathComponent, root: root, tool: newest.tool, phase: RunLog.phase(ofLogAt: newest.url, expectedTests: nil))
        }.sorted { $0.worktree < $1.worktree }
    }

    /// A workspace's newest build or test log, its tool read from its name (`test_sim_2026-…_pid…_….log`); none when the
    /// folder can't be read.
    static func newestLog(in logs: URL) -> (url: URL, tool: String, modified: Date)? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: logs.path)) ?? []
        return names.compactMap { name -> (url: URL, tool: String, modified: Date)? in
            guard let match = name.firstMatch(of: /^((?:build|test)[a-z_]*?)_\d{4}-\d{2}-\d{2}T.*\.log$/), !name.contains("parser-debug") else { return nil }
            let url = logs.appending(path: name)
            guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
            return (url, String(match.1), modified)
        }.max { $0.modified < $1.modified }
    }
}
