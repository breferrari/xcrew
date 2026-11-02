import Foundation

struct ProjectConfigCheck: Check {
    let id = "mobilebuildmcp/project-config"
    let title = "MobileBuildMCP project config"

    /// What the doctor says of the config folder XcodeBuildMCP kept before the rename, at `folder`: it's in the person's
    /// project, maybe tracked in git, so removing it is theirs to agree to, said before the command that ends the text.
    static func legacyFolder(_ folder: String) -> String {
        ".xcodebuildmcp/ predates MobileBuildMCP 2.7.1 and is no longer read. It's in the person's project, so it's the person's to agree to: rm -r \(CorruptModuleCache.quoted(folder))"
    }

    func run(_ context: CheckContext) async -> CheckResult {
        let project = context.project
        guard project.hasMobileBuildMCPConfig, let yaml = try? String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8) else {
            // Its fix writes a MobileBuildMCP config, which only an Apple-platform project has a use for.
            let layout = project.layout(.anywhereButHome)
            guard layout.isApplePlatform else { return .skip("not an Apple project") }
            // Setup alone leaves nothing to build where the project isn't generated yet: the generate is said with it.
            let generate = layout.ungenerated.map { "; the project isn't generated in this checkout yet either: run `\($0.firstGenerateCommand)` from the project's root" } ?? ""
            if await Worktree.takesMainConfig(project, using: context.runner) {
                return .fail("no .mobilebuildmcp/config.yaml in this worktree: \(Worktree.setupCommand) writes it from the main checkout's" + generate)
            }
            return .fail("no .mobilebuildmcp/config.yaml: run /xcrew:setup" + (project.isConfiguredByMCS ? " (or, with the mcs CLI, mcs sync)" : "") + generate)
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
            return .warn(Self.legacyFolder(project.legacyConfigFolder.path))
        }
        let missing = ConfigRenderer.containerPaths(in: yaml, root: project.root, home: context.machine.home).filter { !FileManager.default.fileExists(atPath: $0) }
        if !missing.isEmpty {
            let names = missing.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            // A generator's output is kept out of git, so a checkout made since, as a worktree, has none until it generates.
            // A path that isn't there can't be resolved, so the root is matched as written and as the file system spells it.
            let roots = [project.root.path, project.canonicalRoot].map { $0 + "/" }
            if let manifests = project.layout(.anywhereButHome).generator, missing.allSatisfy({ path in roots.contains { path.hasPrefix($0) } }) {
                return .warn("the config points at \(names), which isn't generated in this checkout yet: run `\(manifests.firstGenerateCommand)` from the project's root")
            }
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
