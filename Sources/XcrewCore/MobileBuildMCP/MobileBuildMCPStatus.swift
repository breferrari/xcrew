import Foundation

/// Whether MobileBuildMCP can serve builds and tests on this Mac, as the doctor and the session briefing both read it.
enum MobileBuildMCPStatus: Sendable, Equatable {
    case usable(version: String)
    case missing
    case outdated(version: String)
    /// `--version` gave nothing in time: the install is suspect, though its server may still run.
    case unreadable

    /// 2.7.1 renamed XcodeBuildMCP's binary, environment variables and config folder, with no fallback to the old
    /// names; everything xcrew writes assumes the new ones.
    static let minimum = Version("2.7.1")

    static func assess(_ machine: Machine, timeout: Duration = .seconds(30)) async -> MobileBuildMCPStatus {
        guard let path = machine.runner.which("mobilebuildmcp") else { return .missing }
        let version = await Self.version(at: path, machine: machine, timeout: timeout)
        if version.isEmpty { return .unreadable }
        return Version(version) >= minimum ? .usable(version: version) : .outdated(version: version)
    }

    /// Why MobileBuildMCP can't serve, and the command that fixes it; nil when it can.
    var problem: (reason: String, fix: String)? {
        switch self {
        case .usable: nil
        case .missing: ("not installed", "brew install getsentry/xcodebuildmcp/mobilebuildmcp")
        case let .outdated(version): ("version \(version) is older than \(Self.minimum)", "brew upgrade mobilebuildmcp")
        case .unreadable: ("its version couldn't be read", "brew reinstall mobilebuildmcp")
        }
    }

    /// Whether builds and tests go to the Xcode MCP instead: not for an unreadable version, which says nothing of the
    /// server Claude Code started.
    var failsOver: Bool {
        switch self {
        case .missing, .outdated: true
        case .usable, .unreadable: false
        }
    }

    /// The installed version, kept beside xcrew's build until the binary changes. Homebrew's link points into a
    /// folder named for the version, so the resolved path and its modification time change with every upgrade.
    static func version(at path: String, machine: Machine, timeout: Duration) async -> String {
        let cache = machine.cacheFolder.appending(path: "mobilebuildmcp-version")
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let key = (try? FileManager.default.attributesOfItem(atPath: resolved)[.modificationDate] as? Date).map { "\(resolved) \($0.timeIntervalSince1970)" }
        if let key, let saved = try? String(contentsOf: cache, encoding: .utf8), saved.hasPrefix(key + "\n") {
            return String(saved.dropFirst(key.count + 1))
        }
        let result = await machine.runner.run("mobilebuildmcp", "--version", timeout: timeout)
        let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key, result.succeeded, !version.isEmpty {
            try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data("\(key)\n\(version)".utf8).write(to: cache, options: .atomic)
        }
        return version
    }
}
