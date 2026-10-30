import Foundation

/// Where a project's Xcode containers are and what generates them. Every question about the project's kind or location
/// asks this, so the answers can't disagree. Each walks the project level by level, nearest first, and stops at its answer.
public struct ProjectLayout: Sendable {
    /// How far below the root a walk goes, chosen by what a miss costs.
    /// A project bundle's own file: `project.pbxproj`, or in Xcode 27.2's JSON format `project.xcproj`, which replaces it
    /// when a project switches format ("Updating your Xcode project configuration file format").
    static let pbxproj = "project.pbxproj"
    static let jsonProject = "project.xcproj"

    /// The file a `.xcodeproj` bundle holds, read in this order wherever a project's contents are read.
    static func projectFile(in bundle: URL) -> URL? {
        [pbxproj, jsonProject].map { bundle.appending(path: $0) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

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

        /// The shell command that regenerates the project from these manifests, run from the root. Without `--no-open`
        /// Tuist opens the workspace in Xcode after every generate.
        public var generateCommand: String {
            switch generator {
            case .tuist: return path.isEmpty ? "tuist generate --no-open" : "tuist generate --no-open --path \(argument)"
            case .xcodeGen: return path.isEmpty ? "xcodegen generate" : "xcodegen generate --spec \(argument)/\(ProjectLayout.xcodeGenSpec)"
            }
        }

        /// Tuist's command that resolves the dependencies its manifests declare.
        public var installCommand: String { path.isEmpty ? "tuist install" : "tuist install --path \(argument)" }

        /// After a change to Tuist's dependencies: a generate alone keeps the ones resolved before.
        public var installAndGenerateCommand: String { installCommand + " && " + generateCommand }

        /// The path as one shell word.
        var argument: String {
            path.allSatisfy { $0.isLetter || $0.isNumber || "/._-".contains($0) } ? path : "'" + path.replacing("'", with: #"'\''"#) + "'"
        }
    }

    /// How many folders below the root a walk looks: a repository often keeps its app in `ios/` or `apps/ios/`.
    static let searchDepth = 2
    /// The folder Tuist keeps its helpers, dependencies and settings in, beside its manifests.
    static let tuistFolder = "Tuist"
    /// Names that mark Tuist wherever they stand.
    static let tuistMarkers = ["Tuist.swift", tuistFolder]
    /// The manifest of a Tuist app's dependencies, which `tuist install` resolves before a generate can use them.
    static let tuistDependencies = "\(tuistFolder)/Package.swift"
    /// Tuist's manifests whose names are also ordinary source-file names. At the root they count by name; below it, only
    /// when they import ProjectDescription, since Tuist may find its root by `.git` alone.
    static let tuistProject = "Project.swift"
    static let tuistWorkspace = "Workspace.swift"
    static let tuistManifests = [tuistProject, tuistWorkspace]
    /// XcodeGen's spec, by the name it reads unless told another.
    static let xcodeGenSpec = "project.yml"
    static let xcodeGenMarkers = [xcodeGenSpec]
    /// Where Tuist writes the files it synthesizes, beside the project that declares them.
    static let derivedFolder = "Derived"
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
            if let tuist = entries.first(where: { isTuistManifest($0.url, countsByName: level == 0) }) { return manifests(.tuist, beside: tuist) }
            return entries.first { named($0.url.lastPathComponent, Self.xcodeGenMarkers) }.map { manifests(.xcodeGen, beside: $0) }
        }
    }

    /// What to run after an edit to `file` before the next build, and the manifests it regenerates, when the generator
    /// reads it; `nearest` is the project's manifests. XcodeGen reads its spec and every spec it includes, wherever
    /// they are. Tuist reads a manifest below its app's folder by the rule detection uses, taking that folder as the
    /// root, and every file in its own folder.
    public func command(after file: URL, nearest: Manifests) -> (manifests: Manifests, command: String)? {
        let path = Self.canonical(file)
        if nearest.generator == .xcodeGen {
            return XcodeGenSpec.reads(path, for: nearest.folder.appending(path: xcodeGenSpec(in: nearest.folder))) ? (nearest, nearest.generateCommand) : nil
        }
        let manifests = tuistApp(holding: file) ?? nearest
        let folder = Self.canonical(manifests.folder) + "/"
        guard path.hasPrefix(folder) else { return nil }
        let relative = String(path.dropFirst(folder.count))
        if named(relative, [Self.tuistDependencies]) { return (manifests, manifests.installAndGenerateCommand) }
        let isBeside = !relative.contains("/")
        let isInTuistFolder = !isBeside && named(String(relative.prefix { $0 != "/" }), [Self.tuistFolder])
        return isInTuistFolder || isTuistManifest(file, countsByName: isBeside) ? (manifests, manifests.generateCommand) : nil
    }

    /// The spec's name in `folder` as detection found it, in whatever case the volume allows.
    func xcodeGenSpec(in folder: URL) -> String {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).first { named($0, Self.xcodeGenMarkers) } ?? Self.xcodeGenSpec
    }

    /// The manifest to edit instead of `file`, as a path from the root, and the manifests whose generate writes it, when a
    /// generator writes it: an edit to it is lost on the next generate. What sits beside the bundle or folder decides:
    /// XcodeGen's spec writes the project it names; a Tuist manifest, by detection's rule, writes the project, the
    /// workspace and the `Derived` folder beside it. A bundle with neither, such as a dependency's checked-in project,
    /// isn't a generator's. `nearest` stands for the project being generated at all.
    public func writer(of file: URL, nearest: Manifests) -> (manifests: Manifests, manifest: String)? {
        let rootPath = Self.canonical(root)
        let path = Self.canonicalCreating(file)
        guard path.hasPrefix(rootPath + "/") else { return nil }
        let components = path.dropFirst(rootPath.count + 1).split(separator: "/").map(String.init)
        guard let index = components.firstIndex(where: { Project.isXcodeContainer($0) || named($0, [Self.derivedFolder]) }) else { return nil }
        let bundle = components[index]
        let folderPath = components[..<index].joined(separator: "/")
        let folder = folderPath.isEmpty ? root : root.appending(path: folderPath)
        let fromRoot = { (name: String) in folderPath.isEmpty ? name : "\(folderPath)/\(name)" }
        let beside = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        if let spec = beside.first(where: { named($0, Self.xcodeGenMarkers) }) {
            let name = (try? String(contentsOf: folder.appending(path: spec), encoding: .utf8)).flatMap(XcodeGenSpec.projectName)
            guard Project.isXcodeProject(bundle), name.map({ named(bundle, ["\($0)\(Project.containerExtensions[1])"]) }) ?? true else { return nil }
            return (Manifests(generator: .xcodeGen, folder: folder, path: folderPath), fromRoot(spec))
        }
        let candidates = Project.isXcodeWorkspace(bundle) ? [Self.tuistWorkspace, Self.tuistProject] : [Self.tuistProject]
        let manifest = candidates.lazy.compactMap { candidate in beside.first { self.named($0, [candidate]) } }
            .first { self.isTuistManifest(folder.appending(path: $0), countsByName: folderPath.isEmpty) }
        guard let manifest else { return nil }
        return (tuistApp(holding: file) ?? nearest, fromRoot(manifest))
    }

    /// `canonical` for a path that may not exist yet, as a Write creating a file gives it: the nearest folder that exists,
    /// canonical, with the rest of the path after it.
    static func canonicalCreating(_ url: URL) -> String {
        var existing = url.standardizedFileURL
        var rest: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.pathComponents.count > 1 {
            rest.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        return ([canonical(existing)] + rest).joined(separator: "/")
    }

    /// The Tuist app `file` is part of: the nearest folder above it, up to the root, holding one of Tuist's markers. A
    /// module's `Project.swift` is the app's to generate, not a project of its own.
    func tuistApp(holding file: URL) -> Manifests? {
        let rootPath = Self.canonical(root)
        var folder = file.deletingLastPathComponent()
        while true {
            let folderPath = Self.canonical(folder)
            guard folderPath == rootPath || folderPath.hasPrefix(rootPath + "/") else { return nil }
            if Self.tuistMarkers.contains(where: { FileManager.default.fileExists(atPath: folder.appending(path: $0).path) }) {
                return Manifests(generator: .tuist, folder: folder, path: String(folderPath.dropFirst(rootPath.count).drop { $0 == "/" }))
            }
            if folderPath == rootPath { return nil }
            folder.deleteLastPathComponent()
        }
    }

    /// Every folder holding Tuist's manifests, nearest first: a repository may keep more than one Tuist app.
    public var tuistFolders: [URL] {
        var found: [URL] = []
        _ = first { entries, level -> Bool? in
            found += entries.filter { isTuistManifest($0.url, countsByName: level == 0) }.map { $0.url.deletingLastPathComponent() }
            return nil
        }
        return found.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    /// Whether this is an Apple-platform project: an Xcode container or a generator's manifest, or a package at the root.
    public var isApplePlatform: Bool {
        first { entries, level in
            entries.contains {
                let name = $0.url.lastPathComponent
                return Project.isXcodeContainer(name) || isTuistManifest($0.url, countsByName: level == 0) || named(name, Self.xcodeGenMarkers)
                    || (level == 0 && named(name, Self.packageMarkers))
            } ? true : nil
        } ?? false
    }

    func named(_ name: String, _ markers: [String]) -> Bool {
        markers.contains { ignoresCase ? $0.caseInsensitiveCompare(name) == .orderedSame : $0 == name }
    }

    /// Whether `file` is Tuist's: a marker, or a manifest name that counts by itself where `countsByName`, else by its import.
    func isTuistManifest(_ file: URL, countsByName: Bool) -> Bool {
        let name = file.lastPathComponent
        if named(name, Self.tuistMarkers) { return true }
        guard named(name, Self.tuistManifests) else { return false }
        return countsByName || Self.importsProjectDescription(file)
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

    /// A canonical path from `root`, itself canonical: the path past `root/`, or the path whole when it's elsewhere.
    static func path(_ path: String, from root: String) -> String {
        path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
    }

    /// One spelling per folder: symlinks, the `/System/Volumes/Data` firmlink and, on a case-insensitive volume,
    /// letter case all resolve to the same path (docs/findings.md).
    static func canonical(_ url: URL) -> String {
        let resolved = url.resolvingSymlinksInPath()
        return (try? resolved.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath) ?? resolved.path
    }

    /// `canonical` for a path, for code outside the module.
    public static func canonicalPath(_ path: String) -> String {
        canonical(URL(fileURLWithPath: path))
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
