import Foundation

/// Where a project's Xcode containers are and what generates them. Every question about the project's kind or location
/// asks this, so the answers can't disagree. Each walks the project level by level, nearest first, and stops at its answer.
public struct ProjectLayout: Sendable {
    /// How far below the root a walk goes, chosen by what a miss costs.
    public enum Reach: Sendable {
        /// Below the root only in a git repository. Session start asks; a miss costs one briefing, and a walk of a
        /// folder such as Downloads would cost every session.
        case repository
        /// Below the root in any folder. A missed generator lets Claude edit a project the next generate overwrites,
        /// and this is asked only when an Xcode tool is in use.
        case anywhereButHome
    }

    public enum Generator: Sendable, Equatable {
        case tuist, xcodeGen
    }

    /// How many folders below the root a walk looks: a repository often keeps its app in `ios/` or `apps/ios/`.
    static let searchDepth = 2
    /// Names that mark Tuist at the root. `Project.swift` and `Workspace.swift` are also ordinary source-file names,
    /// so below the root only Tuist's own `Tuist.swift` or `Tuist/` count.
    static let tuistMarkers = ["Tuist.swift", "Tuist"]
    static let tuistRootMarkers = tuistMarkers + ["Project.swift", "Workspace.swift"]
    static let xcodeGenMarkers = ["project.yml"]
    /// Below the root a package is more often a tool or a server than an app, so it counts at the root only.
    static let packageMarkers = ["Package.swift"]
    /// Folders that hold other projects' code, never this one's manifests.
    static let dependencyFolders: Set = ["node_modules", "Pods", "Carthage", "DerivedData", "build"]

    /// Where the walk starts. Listing a URL doesn't follow a symlink at its end, so a project opened through one is
    /// walked from where it leads.
    let root: URL
    let depth: Int
    /// Whether names match as the volume matches them: a manifest named in another case is the generator's only on a
    /// case-insensitive volume.
    let ignoresCase: Bool

    public init(_ project: Project, reach: Reach) {
        root = project.root.resolvingSymlinksInPath()
        depth = Self.depth(of: project, reach: reach)
        ignoresCase = (try? root.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames) == false
    }

    /// The `.xcworkspace` and `.xcodeproj` paths, relative to the root, at the nearest level that has any: workspaces first, then by name.
    public var containers: [String] {
        let rank = { (path: String) in Project.containerExtensions.firstIndex { path.hasSuffix($0) } ?? 0 }
        return first { entries, _ in
            let found = entries.filter { Project.isXcodeContainer($0.url.lastPathComponent) }.map(\.path)
            return found.isEmpty ? nil : found.sorted { (rank($0), $0) < (rank($1), $1) }
        } ?? []
    }

    /// The generator whose manifests are nearest the root, and the folder holding them: `ios/` for `ios/Tuist.swift`.
    public var generator: (kind: Generator, root: URL)? {
        first { entries, level in
            if let tuist = entries.first(where: { named($0.url.lastPathComponent, level == 0 ? Self.tuistRootMarkers : Self.tuistMarkers) }) {
                return (.tuist, tuist.url.deletingLastPathComponent())
            }
            return entries.first { named($0.url.lastPathComponent, Self.xcodeGenMarkers) }.map { (.xcodeGen, $0.url.deletingLastPathComponent()) }
        }
    }

    /// Whether this is an Apple-platform project: an Xcode container or a generator's manifest, or a package at the root.
    public var isApplePlatform: Bool {
        first { entries, level in
            let markers = level == 0 ? Self.tuistRootMarkers + Self.xcodeGenMarkers + Self.packageMarkers : Self.tuistMarkers + Self.xcodeGenMarkers
            return entries.contains { Project.isXcodeContainer($0.url.lastPathComponent) || named($0.url.lastPathComponent, markers) } ? true : nil
        } ?? false
    }

    func named(_ name: String, _ markers: [String]) -> Bool {
        markers.contains { ignoresCase ? $0.caseInsensitiveCompare(name) == .orderedSame : $0 == name }
    }

    /// Visits the entries of each level, nearest first, and returns the first answer `visit` gives. Each entry carries its
    /// path relative to the root, since the listing may spell the root another way (/private/var for /var).
    func first<Answer>(_ visit: (_ entries: [(url: URL, path: String)], _ level: Int) -> Answer?) -> Answer? {
        var folders = [(url: root, path: "")]
        for level in 0...depth {
            let entries = folders.flatMap { folder in
                ((try? FileManager.default.contentsOfDirectory(at: folder.url, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? [])
                    .map { (url: $0, path: folder.path.isEmpty ? $0.lastPathComponent : "\(folder.path)/\($0.lastPathComponent)") }
            }
            if let answer = visit(entries, level) { return answer }
            guard level < depth else { break }
            folders = entries.filter { Self.isSearched($0.url) }
        }
        return nil
    }

    /// How many folders below the root `reach` walks in `project`. Never any below the home folder: dotfiles kept in
    /// git make it a repository, and below it are Desktop, Documents and Downloads.
    static func depth(of project: Project, reach: Reach) -> Int {
        if let home = project.home, canonical(project.root) == canonical(home) { return 0 }
        switch reach {
        case .anywhereButHome:
            return searchDepth
        case .repository:
            // A worktree or a submodule has a `.git` file rather than a folder.
            return FileManager.default.fileExists(atPath: project.root.appending(path: ".git").path) ? searchDepth : 0
        }
    }

    /// One spelling per folder: symlinks, the `/System/Volumes/Data` firmlink and, on a case-insensitive volume,
    /// letter case all resolve to the same path (docs/findings.md).
    static func canonical(_ url: URL) -> String {
        let resolved = url.resolvingSymlinksInPath()
        return (try? resolved.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath) ?? resolved.path
    }

    /// Whether the walk goes into `entry`: a folder that is neither hidden, a dependency, nor a bundle. A bundle is a
    /// package to the file system, or one of Xcode's own folder types, all named `.xc…`; an asset catalog isn't a
    /// package (docs/findings.md).
    static func isSearched(_ entry: URL) -> Bool {
        guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true, !dependencyFolders.contains(entry.lastPathComponent) else { return false }
        let pathExtension = entry.pathExtension.lowercased()
        // A folder is a package by its extension or by a flag it rarely carries; asking only about named ones spares a lookup per folder.
        return pathExtension.isEmpty || (!pathExtension.hasPrefix("xc") && (try? entry.resourceValues(forKeys: [.isPackageKey]).isPackage) != true)
    }
}
