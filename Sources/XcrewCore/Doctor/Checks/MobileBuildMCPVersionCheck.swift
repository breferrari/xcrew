import Foundation

/// 2.7.1 renamed XcodeBuildMCP's binary, environment variables and config folder, with no
/// fallback to the old names; everything xcrew writes assumes the new ones.
struct MobileBuildMCPVersionCheck: Check {
    static let minimum = Version("2.7.1")
    let id = "mobilebuildmcp/version"
    let title = "MobileBuildMCP \(minimum) or newer"

    func run(_ context: CheckContext) async -> CheckResult {
        guard context.machine.hasMobileBuildMCP else {
            return .fail("not installed: brew install getsentry/xcodebuildmcp/mobilebuildmcp")
        }
        let version = Version(await Self.version(context))
        guard version >= Self.minimum else {
            return .fail("version \(version) is older than \(Self.minimum): brew upgrade mobilebuildmcp")
        }
        return .pass("version \(version)")
    }

    /// The installed version, kept beside xcrew's build until the binary changes. Homebrew's link points into a
    /// folder named for the version, so the resolved path and its modification time change with every upgrade.
    static func version(_ context: CheckContext) async -> String {
        let cache = context.machine.cacheFolder.appending(path: "mobilebuildmcp-version")
        let key = context.runner.which("mobilebuildmcp").flatMap { path -> String? in
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            guard let modified = try? FileManager.default.attributesOfItem(atPath: resolved)[.modificationDate] as? Date else { return nil }
            return "\(resolved) \(modified.timeIntervalSince1970)"
        }
        if let key, let saved = try? String(contentsOf: cache, encoding: .utf8), saved.hasPrefix(key + "\n") {
            return String(saved.dropFirst(key.count + 1))
        }
        let result = await context.runner.run("mobilebuildmcp", "--version")
        let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key, result.succeeded, !version.isEmpty {
            try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data("\(key)\n\(version)".utf8).write(to: cache, options: .atomic)
        }
        return version
    }
}
