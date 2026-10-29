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

    /// The generator a project's manifests name, and the folder holding them: `ios/` for `ios/Tuist.swift`.
    public struct Manifests: Sendable, Equatable {
        public let generator: Generator
        public let folder: URL
        /// The folder's path relative to the root; empty for the root itself.
        public let path: String
    }

    /// How many folders below the root a walk looks: a repository often keeps its app in `ios/` or `apps/ios/`.
    static let searchDepth = 2
    /// Names that mark Tuist wherever they stand.
    static let tuistMarkers = ["Tuist.swift", "Tuist"]
    /// Tuist's manifests whose names are also ordinary source-file names. At the root they count by name; below it, only
    /// when they import ProjectDescription, since Tuist may find its root by `.git` alone.
    static let tuistManifests = ["Project.swift", "Workspace.swift"]
    static let xcodeGenMarkers = ["project.yml"]
    /// Below the root a package is more often a tool or a server than an app, so it counts at the root only.
    static let packageMarkers = ["Package.swift"]
    /// Folders that hold other projects' code, never this one's manifests.
    static let dependencyFolders: Set = ["node_modules", "Pods", "Carthage", "DerivedData", "build"]
    /// How much of a manifest is read to find its imports.
    static let importWindow = 8192

    /// Where the walk starts. Listing a URL doesn't follow a symlink at its end, so a project opened through one is
    /// walked from where it leads.
    let root: URL
    let depth: Int
    /// The home folder's path relative to the root, when it lies below it: never listed, since below it are Desktop,
    /// Documents and Downloads.
    let homePath: String?
    /// Whether names match as the volume matches them: a manifest named in another case is the generator's only on a
    /// case-insensitive volume.
    let ignoresCase: Bool

    public init(_ project: Project, reach: Reach) {
        root = project.root.resolvingSymlinksInPath()
        depth = Self.depth(of: project, reach: reach)
        let rootPath = Self.canonical(project.root) + "/"
        homePath = project.home.map(Self.canonical).flatMap { $0.hasPrefix(rootPath) ? String($0.dropFirst(rootPath.count)) : nil }
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

    /// The manifests nearest the root, Tuist's before XcodeGen's at the same level.
    public var generator: Manifests? {
        first { entries, level in
            if let tuist = entries.first(where: { isTuistManifest($0, level: level) }) { return manifests(.tuist, beside: tuist) }
            return entries.first { named($0.url.lastPathComponent, Self.xcodeGenMarkers) }.map { manifests(.xcodeGen, beside: $0) }
        }
    }

    /// Every folder holding Tuist's manifests, nearest first: a repository may keep more than one Tuist app.
    public var tuistFolders: [URL] {
        var found: [URL] = []
        _ = first { entries, level -> Bool? in
            found += entries.filter { isTuistManifest($0, level: level) }.map { $0.url.deletingLastPathComponent() }
            return nil
        }
        return found.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    /// Whether this is an Apple-platform project: an Xcode container or a generator's manifest, or a package at the root.
    public var isApplePlatform: Bool {
        first { entries, level in
            entries.contains {
                let name = $0.url.lastPathComponent
                return Project.isXcodeContainer(name) || isTuistManifest($0, level: level) || named(name, Self.xcodeGenMarkers)
                    || (level == 0 && named(name, Self.packageMarkers))
            } ? true : nil
        } ?? false
    }

    func named(_ name: String, _ markers: [String]) -> Bool {
        markers.contains { ignoresCase ? $0.caseInsensitiveCompare(name) == .orderedSame : $0 == name }
    }

    func isTuistManifest(_ entry: (url: URL, path: String), level: Int) -> Bool {
        let name = entry.url.lastPathComponent
        if named(name, Self.tuistMarkers) { return true }
        guard named(name, Self.tuistManifests) else { return false }
        return level == 0 || Self.importsProjectDescription(entry.url)
    }

    func manifests(_ generator: Generator, beside entry: (url: URL, path: String)) -> Manifests {
        Manifests(generator: generator, folder: entry.url.deletingLastPathComponent(), path: (entry.path as NSString).deletingLastPathComponent)
    }

    /// Whether a line near the top of `file` imports ProjectDescription, or ProjectDescriptionHelpers, which re-exports it.
    /// A heuristic: a manifest can't describe a project without it, and no doc defines a manifest by its text.
    static func importsProjectDescription(_ file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file), let head = try? handle.read(upToCount: importWindow) else { return false }
        try? handle.close()
        return String(decoding: head, as: UTF8.self).split(whereSeparator: \.isNewline).contains {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("import ProjectDescription")
        }
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
            folders = entries.filter { $0.path != homePath && Self.isSearched($0.url) }
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
