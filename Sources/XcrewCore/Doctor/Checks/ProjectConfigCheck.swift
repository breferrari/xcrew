import Foundation

struct ProjectConfigCheck: Check {
    let id = "mobilebuildmcp/project-config"
    let title = "MobileBuildMCP project config"

    func run(_ context: CheckContext) async -> CheckResult {
        let project = context.project
        guard project.hasMobileBuildMCPConfig, let yaml = try? String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8) else {
            // Its fix writes a MobileBuildMCP config, which only an Apple-platform project has a use for.
            guard project.layout(.anywhereButHome).isApplePlatform else { return .skip("not an Apple project") }
            if await Worktree.takesMainConfig(project, using: context.runner) {
                return .fail("no .mobilebuildmcp/config.yaml in this worktree: \(Worktree.setupCommand) writes it from the main checkout's")
            }
            return .fail("no .mobilebuildmcp/config.yaml: run /xcrew:setup" + (project.isConfiguredByMCS ? " (or, with the mcs CLI, mcs sync)" : ""))
        }
        let lists = ConfigRenderer.lists(in: yaml)
        let kept = ConfigWriter.keeping(project)
        let force = switch kept {
        case .keptUnmanaged: " (xcrew setup --force replaces a config xcrew didn't write)"
        case .keptEdited: " (xcrew setup --force replaces it, as it changed after Xcrew wrote it)"
        case .written, nil: ""
        }
        // Said first: the warnings below can stay for good, and this one hides runs from the mod.
        if ConfigRenderer.reachesXcodeIDE(lists) {
            return .warn("the config enables xcode-ide, MobileBuildMCP's second route to the Xcode MCP, whose answers Xcrew can't read: /xcrew:setup rewrites it" + force)
        }
        if FileManager.default.fileExists(atPath: project.legacyConfigFolder.path) {
            return .warn(".xcodebuildmcp/ predates MobileBuildMCP 2.7.1 and is no longer read: delete it")
        }
        let missing = ConfigRenderer.containerPaths(in: yaml, root: project.root, home: context.machine.home).filter { !FileManager.default.fileExists(atPath: $0) }
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
        if kept != .keptUnmanaged, !ConfigRenderer.hasCurrentToolGroups(lists) {
            return .warn("the config Xcrew wrote has other tool groups than setup writes now: /xcrew:setup rewrites it" + force)
        }
        if yaml.contains("incrementalBuildsEnabled: true") {
            return .warn("incremental builds are on; they were slower in testing and write a Makefile into the project")
        }
        return .pass(".mobilebuildmcp/config.yaml")
    }
}
