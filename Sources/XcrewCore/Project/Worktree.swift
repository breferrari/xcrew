import Foundation

/// A linked git worktree, as `git worktree add` or Claude Code's `--worktree` makes one, and the main checkout it belongs
/// to. Setup keeps `.mobilebuildmcp/` out of git, so a worktree starts without the main checkout's config
/// (docs/findings.md, *Worktree sessions*).
public enum Worktree {
    /// Said at the start, and by the mod with the session's first MobileBuildMCP build or test, in a worktree that
    /// `takesMainConfig`: a fact and the setup that copies the main checkout's config, never an instruction.
    public static let setupOffer = "This worktree has no MobileBuildMCP config of its own yet; `xcrew setup --worktree` writes one from the main checkout's."

    /// Whether `project` is a linked worktree with no config whose main checkout has one, for setup to copy.
    public static func takesMainConfig(_ project: Project, using runner: any CommandRunning) async -> Bool {
        guard !project.hasMobileBuildMCPConfig, let main = await mainCheckout(of: project, using: runner) else { return false }
        return Project(root: main).hasMobileBuildMCPConfig
    }

    /// The main checkout of the linked worktree `project` is in; nil in a main checkout, in a worktree of a bare
    /// repository, which has none, and outside git.
    public static func mainCheckout(of project: Project, using runner: any CommandRunning) async -> URL? {
        let ran = await runner.run("git", "-C", project.root.path, "rev-parse", "--path-format=absolute", "--git-dir", "--git-common-dir")
        let folders = ran.stdout.split(whereSeparator: \.isNewline).map { URL(fileURLWithPath: String($0)) }
        guard ran.succeeded, folders.count == 2, ProjectLayout.canonical(folders[0]) != ProjectLayout.canonical(folders[1]),
              folders[1].lastPathComponent == ".git"
        else { return nil }
        return folders[1].deletingLastPathComponent()
    }

    /// The main checkout's config as a worktree takes it: each path MobileBuildMCP reads (`CarriedDefaults.pathKeys`)
    /// that's absolute is left out, since it lies outside the checkout and every worktree would share it, DerivedData
    /// above all; a path written from the root works in the worktree as it is. The paths left out come back too.
    public static func config(from yaml: String) -> (yaml: String, leftOut: [(key: String, path: String)]) {
        var leftOut: [(key: String, path: String)] = []
        let kept = yaml.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let key = CarriedDefaults.pathKeys.first(where: { trimmed.hasPrefix("\($0):") }) else { return true }
            // Quoted either way: xcrew writes single quotes, and a person may write double.
            let value = ConfigRenderer.unquoted(trimmed.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard value.hasPrefix("/") || value.hasPrefix("~") else { return true }
            leftOut.append((key, value))
            return false
        }
        return (kept.joined(separator: "\n"), leftOut)
    }
}
