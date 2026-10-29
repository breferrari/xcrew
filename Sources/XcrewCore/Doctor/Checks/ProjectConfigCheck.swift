import Foundation

struct ProjectConfigCheck: Check {
    let id = "mobilebuildmcp/project-config"
    let title = "MobileBuildMCP project config"

    func run(_ context: CheckContext) async -> CheckResult {
        let project = context.project
        guard project.hasMobileBuildMCPConfig, let yaml = try? String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8) else {
            // Its fix writes a MobileBuildMCP config, which only an Apple-platform project has a use for.
            guard project.layout(.anywhereButHome).isApplePlatform else { return .skip("not an Apple project") }
            return .fail("no .mobilebuildmcp/config.yaml: run /xcrew:setup (or, with the mcs CLI, mcs sync)")
        }
        if FileManager.default.fileExists(atPath: project.legacyConfigFolder.path) {
            return .warn(".xcodebuildmcp/ predates MobileBuildMCP 2.7.1 and is no longer read: delete it")
        }
        let missing = ConfigRenderer.containerPaths(in: yaml).filter { !FileManager.default.fileExists(atPath: $0) }
        if !missing.isEmpty {
            let names = missing.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            return .warn("the config points at \(names), which no longer exists (the project moved or was renamed): xcrew setup")
        }
        let profiles = ConfigRenderer.profiles(in: yaml)
        if let active = profiles.active, !profiles.withScheme.contains(active) {
            return .warn("the active profile, \(active), has no scheme, so a build or test has nothing to run: rerun /xcrew:setup (xcrew setup --force replaces a config xcrew didn't write)")
        }
        if profiles.withScheme.isEmpty {
            return .warn("no profile has a scheme yet, so a build or test needs one each time: /xcrew:setup adds them from your schemes")
        }
        if !yaml.contains("- xcode-ide") {
            return .warn("the xcode-ide tool group is off; another tool may have rewritten the config (xcrew setup --force restores it)")
        }
        if yaml.contains("incrementalBuildsEnabled: true") {
            return .warn("incremental builds are on; they were slower in testing and write a Makefile into the project")
        }
        return .pass(".mobilebuildmcp/config.yaml")
    }
}
