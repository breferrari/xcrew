import Foundation

/// The MobileBuildMCP runs going in the project's other worktrees, read from the logs MobileBuildMCP writes as a run goes.
public enum OtherRuns {
    public struct Run: Sendable, Equatable, Codable {
        /// The worktree's folder name, as the person knows it, whatever folder the project sits in within it.
        public let worktree: String
        /// The tool that writes the log, from its name: `test_sim`.
        public let tool: String
        /// What the run is doing, as the band says it for this session's own run; nil when the log doesn't say yet.
        public let phase: String?
    }

    /// How long a log may go unwritten and its run still count as going: xcodebuild is quiet through a link, a long test
    /// or a simulator's boot. The mod clears what it shows after as long.
    public static let quietFor: TimeInterval = 90

    /// The xcodebuild tools whose logs end on a verdict (`build_sim`, `build_run_device`, `test_macos`) and the time their
    /// log's name starts with; a Swift package's build (`build_spm`) never prints one.
    static var runLog: Regex<(Substring, Substring)> { /^((?:build|test)(?:_run)?_(?:sim|device|macos))_\d{4}-\d{2}-\d{2}T/ }

    /// Each of the project's other worktrees' newest xcodebuild log written within `quietFor` that has no verdict yet; none
    /// outside git, and none from a worktree whose folder is gone or whose workspace can't be read.
    public static func going(project: Project, machine: Machine, now: Date) async -> [Run] {
        let here = ProjectLayout.canonical(project.root)
        var tops: [String: String] = [:]
        for checkout in await ProjectWorkspaces.live(of: project, using: machine.runner) { tops[checkout.root] = checkout.top }
        return tops.compactMap { root, top -> Run? in
            guard ProjectLayout.canonicalPath(root) != here, FileManager.default.fileExists(atPath: root),
                  let log = RunLog.find(since: now.addingTimeInterval(-quietFor), project: URL(fileURLWithPath: root), home: machine.home, named: { $0.firstMatch(of: runLog) != nil }),
                  let tool = log.lastPathComponent.firstMatch(of: runLog).map({ String($0.1) }) else { return nil }
            guard RunLog.outcome(of: RunLog.end(ofLogAt: log.path), kind: tool.hasPrefix("test") ? .test : .build) == nil else { return nil }
            return Run(worktree: URL(fileURLWithPath: top).lastPathComponent, tool: tool, phase: RunLog.phase(ofLogAt: log, expectedTests: nil))
        }.sorted { $0.worktree < $1.worktree }
    }
}
