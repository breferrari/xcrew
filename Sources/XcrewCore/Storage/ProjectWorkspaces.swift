import CryptoKit
import Foundation

/// The MobileBuildMCP workspaces a project's checkouts use, and the root a workspace served. MobileBuildMCP keys a
/// workspace by its root (`RunLog.workspaceKey`) and records no root, and its family is the root's folder name alone, so
/// a project's worktrees are families apart (docs/findings.md, *Disk space*).
public enum ProjectWorkspaces {
    public struct Checkout: Sendable, Equatable {
        public let root: String
        public let key: String
    }

    /// Each live checkout of the project, the main one and every worktree `git worktree list` names, at the project's
    /// folder in it, with its key as written and as the file system spells it. Outside git, the project alone.
    static func live(of project: Project, using runner: any CommandRunning) async -> [Checkout] {
        let git = { (arguments: String...) in await runner.run(["git", "-C", project.root.path] + arguments, stdin: nil, timeout: .seconds(10)) }
        async let prefixed = git("rev-parse", "--show-prefix")
        let listed = await git("worktree", "list", "--porcelain")
        let prefix = await prefixed.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let tops = listed.succeeded
            ? listed.stdout.components(separatedBy: "\n\n").compactMap { block -> String? in
                let lines = block.split(separator: "\n")
                guard !lines.contains("bare") else { return nil }
                return lines.first { $0.hasPrefix("worktree ") }.map { String($0.dropFirst("worktree ".count)) }
            }
            : []
        let roots = tops.isEmpty ? [project.root.path] : tops.map { prefix.isEmpty ? $0 : URL(fileURLWithPath: $0).appending(path: prefix).path }
        var seen: Set<String> = []
        return roots.flatMap { root in
            [root, ProjectLayout.canonicalPath(root)].map(RunLog.workspaceKey(root:)).filter { seen.insert($0).inserted }.map { Checkout(root: root, key: $0) }
        }
    }

    /// How many of a workspace's newest logs are read for its root, and how much of each.
    static let logsRead = 3
    static let logBytes = 256 * 1024

    /// The root a workspace served, from the container its newest build logs name: the container's folder, or one a few
    /// above it, whose hash is the key's. None when no log names one, or none of its folders hashes to the key.
    static func root(ofWorkspace folder: URL) -> String? {
        guard let hash = folder.lastPathComponent.firstMatch(of: /-([0-9a-f]{12})$/)?.1 else { return nil }
        let logs = folder.appending(path: "logs")
        let manager = FileManager.default
        let modified = { (url: URL) in (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast }
        let newest = ((try? manager.contentsOfDirectory(at: logs, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .sorted { modified($0) > modified($1) }.prefix(logsRead)
        for log in newest {
            guard let handle = try? FileHandle(forReadingFrom: log), let data = try? handle.read(upToCount: logBytes) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            guard let named = text.firstMatch(of: /-(?:workspace|project) (?:'([^']+)'|"([^"]+)"|(\S+\.xc(?:workspace|odeproj)))/) else { continue }
            var candidate = URL(fileURLWithPath: String(named.1 ?? named.2 ?? named.3 ?? "")).deletingLastPathComponent()
            for _ in 0..<4 {
                if SHA256.hash(data: Data(candidate.path.utf8)).hex.hasPrefix(hash) { return candidate.path }
                candidate.deleteLastPathComponent()
            }
        }
        return nil
    }
}
