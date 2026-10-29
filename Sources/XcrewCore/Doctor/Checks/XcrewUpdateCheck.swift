import Foundation

/// Whether a newer Xcrew is out. Claude Code updates a third-party marketplace's plugins only
/// once the person turns on auto-update, so without it nothing else says a release exists.
struct XcrewUpdateCheck: Check {
    static let latestRelease = "https://api.github.com/repos/breferrari/xcrew/releases/latest"
    let id = "xcrew/up-to-date"
    let title = "Xcrew is the latest release"
    let reachesNetwork = true

    func run(_ context: CheckContext) async -> CheckResult {
        async let commit = Self.commit(context)
        let response = await context.runner.run("curl", "-fsSL", "--max-time", "5", Self.latestRelease)
        let checkout = await commit
        let installed = XcrewVersion.current + (checkout.map { " (\($0))" } ?? "")
        let release = try? JSONSerialization.jsonObject(with: Data(response.stdout.utf8)) as? [String: Any]
        guard response.status == 0, let tag = release?["tag_name"] as? String else {
            return .skip("\(installed): couldn't reach GitHub to compare")
        }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard Version(XcrewVersion.current) < Version(latest) else {
            return .pass("\(installed), the latest release")
        }
        let update = checkout == nil
            ? "claude plugin update xcrew@breferrari, or turn on auto-update in /plugin → Marketplaces → breferrari"
            : "git pull in \(context.machine.value("XCREW_ROOT") ?? ".")"
        return .warn("\(installed) installed, \(latest) released: \(update)")
    }

    /// The commit a git checkout of Xcrew runs (`--plugin-dir`, a clone), with `+ local changes` when its tree differs.
    /// An empty prefix means the root is the repository's top level, whatever spelling of the path the caller used.
    private static func commit(_ context: CheckContext) async -> String? {
        guard let root = context.machine.value("XCREW_ROOT") else { return nil }
        let head = await context.runner.run("git", "-C", root, "rev-parse", "--show-prefix", "--short", "HEAD")
        let lines = head.stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard head.succeeded, lines.count >= 2, lines[0].isEmpty, !lines[1].isEmpty else { return nil }
        let status = await context.runner.run("git", "--no-optional-locks", "-C", root, "status", "--porcelain")
        guard status.succeeded else { return nil }
        return status.stdout.isEmpty ? lines[1] : "\(lines[1]) + local changes"
    }
}
