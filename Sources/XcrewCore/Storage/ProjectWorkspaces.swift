import Foundation

/// The MobileBuildMCP workspaces a project's checkouts use, and the root a workspace served. MobileBuildMCP keys a
/// workspace by its root (`RunLog.workspaceKey`) and records no root, and its family is the root's folder name alone, so
/// a project's worktrees are families apart (docs/findings.md, *Disk space*).
public enum ProjectWorkspaces {
    public struct Checkout: Sendable, Equatable {
        public let root: String
        public let key: String
    }

    /// Where a workspace's project is: one of this project's live checkouts, a root its log names that's gone or still
    /// here, or unknown.
    public enum Origin: Sendable, Equatable {
        case live(Checkout)
        case gone(String)
        case elsewhere(String)
        case unknown
    }

    /// Each live checkout of the project, the main one and every worktree `git worktree list` names but a bare or a
    /// prunable one, at the project's folder in it, with its key as written and as the file system spells it. Outside
    /// git, the project alone.
    static func live(of project: Project, using runner: any CommandRunning) async -> [Checkout] {
        let git = { (arguments: String...) in await runner.run(["git", "-C", project.root.path] + arguments, stdin: nil, timeout: .seconds(10)) }
        async let prefixed = git("rev-parse", "--show-prefix")
        let listed = await git("worktree", "list", "--porcelain")
        let prefix = await prefixed.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let tops = listed.succeeded ? Worktree.checkouts(listed: listed.stdout).filter { !$0.isBare && !$0.isPrunable }.map(\.top) : []
        let roots = tops.isEmpty ? [project.root.path] : tops.map { prefix.isEmpty ? $0 : URL(fileURLWithPath: $0).appending(path: prefix).path }
        var seen: Set<String> = []
        return roots.flatMap { root in
            [root, ProjectLayout.canonicalPath(root)].map(RunLog.workspaceKey(root:)).filter { seen.insert($0).inserted }.map { Checkout(root: root, key: $0) }
        }
    }

    /// How many workspaces' logs are read at once.
    static let readAtOnce = 8

    /// Each workspace's origin, its logs read a few workspaces at a time.
    public static func origins(of report: StorageReport, live: [Checkout], home: URL) async -> [String: Origin] {
        await withTaskGroup(of: (String, Origin).self) { group in
            var pending = report.workspaces.makeIterator()
            func next() {
                guard let workspace = pending.next() else { return }
                group.addTask {
                    if let checkout = live.first(where: { $0.key == workspace.key }) { return (workspace.key, .live(checkout)) }
                    let folder = workspace.folder.hasPrefix("~/") ? home.appending(path: String(workspace.folder.dropFirst(2))) : URL(fileURLWithPath: workspace.folder)
                    guard let root = root(ofWorkspace: folder) else { return (workspace.key, .unknown) }
                    return (workspace.key, FileManager.default.fileExists(atPath: root) ? .elsewhere(root) : .gone(root))
                }
            }
            for _ in 0..<readAtOnce { next() }
            var origins: [String: Origin] = [:]
            while let (key, origin) = await group.next() {
                origins[key] = origin
                next()
            }
            return origins
        }
    }

    /// How much of each of a workspace's newest logs is read for its root: the command naming the container comes first.
    static let logsRead = 3
    static let logBytes = 64 * 1024

    /// The root a workspace served, from the container its newest build logs name: the container's folder, or one a few
    /// above it, whose key is the workspace's. None when no log names one, or none of its folders has the key.
    static func root(ofWorkspace folder: URL) -> String? {
        let key = folder.lastPathComponent
        let logs = (try? FileManager.default.contentsOfDirectory(at: folder.appending(path: "logs"), includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for log in logs.sorted(by: { EvidencePack.modified($0) > EvidencePack.modified($1) }).prefix(logsRead) {
            guard let handle = try? FileHandle(forReadingFrom: log), let data = try? handle.read(upToCount: logBytes) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            guard let named = text.firstMatch(of: /-(?:workspace|project) (?:'([^']+)'|"([^"]+)"|(\S+\.xc(?:workspace|odeproj)))/) else { continue }
            var candidate = URL(fileURLWithPath: String(named.1 ?? named.2 ?? named.3 ?? "")).deletingLastPathComponent()
            for _ in 0..<4 {
                if RunLog.workspaceKey(root: candidate.path) == key { return candidate.path }
                candidate.deleteLastPathComponent()
            }
        }
        return nil
    }
}
