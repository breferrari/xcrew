import Foundation

struct ProjectConfigCheck: Check {
    let id = "mobilebuildmcp/project-config"
    let title = "MobileBuildMCP project config"

    func run(_ context: CheckContext) async -> CheckResult {
        let project = context.project
        guard project.hasMobileBuildMCPConfig, let yaml = try? String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8) else {
            // Its fix writes a MobileBuildMCP config, which only an Apple-platform project has a use for.
            guard project.layout(.anywhereButHome).isApplePlatform else { return .skip("not an Apple project") }
            return .fail("no .mobilebuildmcp/config.yaml: run /xcrew:setup, or mcs sync")
        }
        if FileManager.default.fileExists(atPath: project.legacyConfigFolder.path) {
            return .warn(".xcodebuildmcp/ predates MobileBuildMCP 2.7.1 and is no longer read: delete it")
        }
        let missing = ConfigRenderer.containerPaths(in: yaml).filter { !FileManager.default.fileExists(atPath: $0) }
        if !missing.isEmpty {
            let names = missing.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            return .warn("the config points at \(names), which no longer exists (the project moved or was renamed): xcrew setup")
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
