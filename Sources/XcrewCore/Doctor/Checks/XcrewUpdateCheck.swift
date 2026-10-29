import Foundation

/// Whether a newer Xcrew is out. Claude Code updates a third-party marketplace's plugins only
/// once the person turns on auto-update, so without it nothing else says a release exists.
struct XcrewUpdateCheck: Check {
    static let latestRelease = "https://api.github.com/repos/breferrari/xcrew/releases/latest"
    let id = "xcrew/up-to-date"
    let title = "Xcrew is the latest release"
    let reachesNetwork = true
    let isCoveredByMCS = true

    func run(_ context: CheckContext) async -> CheckResult {
        let response = await context.runner.run("curl", "-fsSL", "--max-time", "5", Self.latestRelease)
        let release = try? JSONSerialization.jsonObject(with: Data(response.stdout.utf8)) as? [String: Any]
        guard response.status == 0, let tag = release?["tag_name"] as? String else {
            return .skip("couldn't reach GitHub to compare")
        }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard Version(XcrewVersion.current) < Version(latest) else {
            return .pass("\(XcrewVersion.current), the latest release")
        }
        return .warn("\(XcrewVersion.current) installed, \(latest) released: claude plugin update xcrew@breferrari, or turn on auto-update in /plugin → Marketplaces → breferrari")
    }
}
