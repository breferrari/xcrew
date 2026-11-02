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
        await others(of: project, machine: machine).compactMap { root, top -> Run? in
            guard FileManager.default.fileExists(atPath: root),
                  let log = RunLog.find(since: now.addingTimeInterval(-quietFor), project: URL(fileURLWithPath: root), home: machine.home, named: { $0.firstMatch(of: runLog) != nil }),
                  let tool = log.lastPathComponent.firstMatch(of: runLog).map({ String($0.1) }) else { return nil }
            let followed = RunLog.follow(logAt: log, expectedTests: nil, kind: tool.hasPrefix("test") ? .test : .build, keptIn: RunLog.readings(on: machine))
            guard followed?.outcome == nil else { return nil }
            return Run(worktree: URL(fileURLWithPath: top).lastPathComponent, tool: tool, phase: followed?.phase)
        }.sorted { $0.worktree < $1.worktree }
    }

    /// The other worktrees whose xcodebuild run went while this checkout's went, from `from` to `to`: one whose log opened
    /// before `to` and was last written at or after `from`, ended since or not. Their folder names, sorted; none outside
    /// git. A run in this time shares the Mac's cores, so its length says nothing of a run on its own.
    public static func overlapped(project: Project, machine: Machine, from: Date, to: Date) async -> [String] {
        let until = Int(to.timeIntervalSince1970 * 1000)
        let names = await others(of: project, machine: machine).compactMap { root, top -> String? in
            let logs = RunLog.candidates(project: URL(fileURLWithPath: root), home: machine.home) { $0.firstMatch(of: runLog) != nil }
            let went = RunLog.newest(logs, since: from).contains { log in
                let name = log.lastPathComponent
                return name.firstMatch(of: runLog).flatMap { RunLog.openedAt(name, tool: String($0.1)) }.map { $0 < until } ?? false
            }
            return went ? URL(fileURLWithPath: top).lastPathComponent : nil
        }
        return Set(names).sorted()
    }

    /// The project's other live worktrees: each one's project root, and the worktree's top folder.
    static func others(of project: Project, machine: Machine) async -> [(root: String, top: String)] {
        let here = ProjectLayout.canonical(project.root)
        var tops: [String: String] = [:]
        for checkout in await ProjectWorkspaces.live(of: project, using: machine.runner) { tops[checkout.root] = checkout.top }
        return tops.filter { ProjectLayout.canonicalPath($0.key) != here }.map { (root: $0.key, top: $0.value) }
    }
}
