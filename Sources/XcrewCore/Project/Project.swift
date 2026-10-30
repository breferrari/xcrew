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
    /// Whether MobileBuildMCP has its per-project config.
    public var hasMobileBuildMCPConfig: Bool { FileManager.default.fileExists(atPath: mobileBuildMCPConfig.path) }
    /// The scheme MobileBuildMCP builds this project with when a call names none; nil without a config or one.
    public var schemeToBuild: String? {
        (try? String(contentsOf: mobileBuildMCPConfig, encoding: .utf8)).flatMap(ConfigRenderer.schemeToBuild)
    }

    /// Whether MobileBuildMCP has a scheme to build this project with. MobileBuildMCP writes a config itself when Claude
    /// saves session defaults, so a config alone doesn't say setup ran.
    public var hasSchemeToBuild: Bool {
        guard let yaml = try? String(contentsOf: mobileBuildMCPConfig, encoding: .utf8) else { return false }
        return ConfigRenderer.hasSchemeToBuild(in: yaml)
    }
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

    /// The file a project pins its Xcode in, as xcodes' `XCODE_VERSION.md` names it: one version, beside the project or
    /// its workspace.
    public static let xcodePinFile = ".xcode-version"

    /// The Xcode the project pins and the file it's in: at the root, else beside one of its Xcode containers, which are
    /// looked for only when the root has none.
    public var xcodePin: (version: String, file: String)? {
        func read(_ file: String) -> (version: String, file: String)? {
            pinned(at: file).map { ($0, file) }
        }
        if let pin = read(Self.xcodePinFile) { return pin }
        let folders = Set(xcodeContainers.map { URL(fileURLWithPath: $0).deletingLastPathComponent().relativePath }).subtracting(["."]).sorted()
        return folders.lazy.compactMap { read("\($0)/\(Self.xcodePinFile)") }.first
    }

    /// What a pin file at `path` from the root holds, trimmed: a small regular file inside the project, so a workflow can't
    /// send it outside, to a device or a pipe. Nil without one, or when it's empty.
    func pinned(at path: String) -> String? {
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
              let values = try? root.appending(path: path).resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, (values.fileSize ?? 0) <= 1024,
              let text = try? String(contentsOf: root.appending(path: path), encoding: .utf8)
        else { return nil }
        let version = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }

    /// The bundles that hold an Xcode workspace or project, workspaces first.
    public static let containerExtensions = [".xcworkspace", ".xcodeproj"]

    static func isXcodeContainer(_ name: String) -> Bool {
        containerExtensions.contains { name.hasSuffix($0) }
    }

    static func isXcodeWorkspace(_ name: String) -> Bool {
        name.hasSuffix(containerExtensions[0])
    }

    static func isXcodeProject(_ name: String) -> Bool {
        name.hasSuffix(containerExtensions[1])
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
