import Foundation

/// A linked git worktree, as `git worktree add` or Claude Code's `--worktree` makes one, and the main checkout it belongs
/// to. Setup keeps `.mobilebuildmcp/` out of git, so a worktree starts without the main checkout's config
/// (docs/findings.md, *Worktree sessions*).
public enum Worktree {
    /// The command that writes a worktree's config from its main checkout's.
    public static let setupCommand = "xcrew setup --worktree"

    /// Said at the start, and by the mod with the session's first MobileBuildMCP build or test, in a worktree that
    /// `takesMainConfig`: a fact and the setup that copies the main checkout's config, never an instruction.
    public static let setupOffer = "This worktree has no MobileBuildMCP config of its own yet; `\(setupCommand)` writes one from the main checkout's."

    /// Whether `project` is a linked worktree with no config whose main checkout has one that names a scheme to build.
    public static func takesMainConfig(_ project: Project, using runner: any CommandRunning) async -> Bool {
        guard !project.hasMobileBuildMCPConfig, let main = await mainCheckout(of: project, using: runner) else { return false }
        return Project(root: main).hasSchemeToBuild
    }

    /// The folder in the main checkout that matches `project`'s in its linked worktree: the main checkout's top level, and
    /// the same folder below it when the project sits a folder down. Nil in a main checkout, in a worktree of a bare
    /// repository, which has no main checkout, and outside git.
    public static func mainCheckout(of project: Project, using runner: any CommandRunning) async -> URL? {
        await checkout(of: project, using: runner).map { $0.main.appending(path: $0.prefix) }
    }

    /// The main checkout's top level, and the project's folder below a checkout's top: empty when the project is at it.
    /// Nil where `mainCheckout` is.
    public static func checkout(of project: Project, using runner: any CommandRunning) async -> (main: URL, prefix: String)? {
        let ran = await runner.run("git", "-C", project.root.path, "rev-parse", "--path-format=absolute", "--git-dir", "--git-common-dir", "--show-prefix")
        let lines = ran.stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard ran.succeeded, lines.count >= 2,
              ProjectLayout.canonical(URL(fileURLWithPath: lines[0])) != ProjectLayout.canonical(URL(fileURLWithPath: lines[1]))
        else { return nil }
        // The main worktree is the first `git worktree list` names; a bare repository's is marked `bare`.
        let listed = await runner.run("git", "-C", project.root.path, "worktree", "list", "--porcelain").stdout
        let first = listed.components(separatedBy: "\n\n").first?.split(separator: "\n") ?? []
        guard let top = first.first(where: { $0.hasPrefix("worktree ") })?.dropFirst("worktree ".count), !first.contains("bare") else { return nil }
        return (URL(fileURLWithPath: String(top)), lines.count > 2 ? lines[2] : "")
    }

    /// The main checkout's config as a worktree takes it, each path MobileBuildMCP reads (`ConfigRenderer.pathKeys`)
    /// reaching the worktree's own: one inside the main checkout written from the root instead; one outside it kept,
    /// except a DerivedData, which is left out, since every worktree would build into it; one written from the root
    /// already, as it is. The paths left out come back too.
    public static func config(from yaml: String, main: URL) -> (yaml: String, leftOut: [(key: String, path: String)]) {
        var leftOut: [(key: String, path: String)] = []
        var lines: [String] = []
        for line in yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            guard let key = ConfigRenderer.pathKeys.first(where: { ConfigRenderer.value(of: $0, in: line) != nil }),
                  let value = ConfigRenderer.value(of: key, in: line), value.hasPrefix("/") || value.hasPrefix("~")
            else {
                lines.append(line)
                continue
            }
            let written = ConfigRenderer.relative(value, to: main)
            if written != value {
                lines.append(String(line.prefix { $0 == " " }) + "\(key): " + ConfigRenderer.quoted(written))
            } else if key == "derivedDataPath" {
                leftOut.append((key, value))
            } else {
                lines.append(line)
            }
        }
        return (lines.joined(separator: "\n"), leftOut)
    }
}
