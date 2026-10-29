import Foundation

/// The project xcrew serves: its root folder and the files xcrew reads or writes there.
public struct Project: Sendable, Equatable {
    public let root: URL
    /// The user's home folder, never searched below even when it's a repository.
    public let home: URL?

    public init(root: URL, home: URL? = nil) {
        self.root = root.standardizedFileURL
        self.home = home?.standardizedFileURL
    }

    /// The project mcs or Claude Code names, else the working directory.
    public static func current(machine: Machine = .live) -> Project {
        let path = machine.value("MCS_PROJECT_PATH") ?? machine.value("CLAUDE_PROJECT_DIR") ?? FileManager.default.currentDirectoryPath
        return Project(root: URL(fileURLWithPath: path, isDirectory: true), home: machine.home)
    }

    public var mobileBuildMCPConfig: URL { root.appending(path: ".mobilebuildmcp/config.yaml") }
    /// Whether MobileBuildMCP has its per-project config; the doctor and the session briefing both ask.
    public var hasMobileBuildMCPConfig: Bool { FileManager.default.fileExists(atPath: mobileBuildMCPConfig.path) }
    /// Whether mcs configured xcrew here: `xcrew` is in `.claude/.mcs-project`'s `configuredPacks`.
    public var isConfiguredByMCS: Bool {
        struct State: Decodable { let configuredPacks: [String]? }
        guard let data = try? Data(contentsOf: root.appending(path: ".claude/.mcs-project")),
              let state = try? JSONDecoder().decode(State.self, from: data) else { return false }
        return state.configuredPacks?.contains("xcrew") == true
    }
    /// Marks the config as xcrew's: setup rewrites a marked config and leaves an unmarked one alone.
    public var managedMarker: URL { root.appending(path: ".mobilebuildmcp/.xcrew-managed") }
    /// Where XcodeBuildMCP kept its config before the rename; no longer read by anything.
    public var legacyConfigFolder: URL { root.appending(path: ".xcodebuildmcp") }
    public var skillsFolder: URL { root.appending(path: ".claude/skills") }

    /// Where the project's Xcode containers are and what generates them, walking as far as `reach` allows.
    public func layout(_ reach: ProjectLayout.Reach) -> ProjectLayout {
        ProjectLayout(self, reach: reach)
    }

    /// `.xcworkspace` and `.xcodeproj` paths relative to the root, nearest first and workspaces first: setup's default container.
    public var xcodeContainers: [String] { layout(.anywhereButHome).containers }

    /// The bundles that hold an Xcode workspace or project, workspaces first.
    public static let containerExtensions = [".xcworkspace", ".xcodeproj"]

    static func isXcodeContainer(_ name: String) -> Bool {
        containerExtensions.contains { name.hasSuffix($0) }
    }

    /// How far below the root session start searches this project.
    var searchDepth: Int { ProjectLayout.depth(of: self, reach: .repository) }

    /// Whether Tuist generates this project, so the macro-copy-phase check looks for its derived projects.
    public var isTuistProject: Bool { layout(.anywhereButHome).generator?.generator == .tuist }

    /// Whether Tuist or XcodeGen generates this project, so its project files are rewritten on each generate.
    public var isGenerated: Bool { layout(.anywhereButHome).generator != nil }

    /// The root as the file system spells it: symlinks resolved, `/private` kept, in the volume's own case.
    public var canonicalRoot: String { ProjectLayout.canonical(root) }

    /// Whether this is an Apple-platform project: what session start asks before briefing Claude.
    public var isApplePlatformProject: Bool { layout(.repository).isApplePlatform }
}
