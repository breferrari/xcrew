import Foundation

/// The build phase Tuist generated before 4.203 for each macro target. It `cp -f`s the macOS
/// plugin into the active destination's products, overwriting the file in place, which gets the
/// plugin killed at its next launch. Tuist 4.203 removed it (tuist#11825).
public enum MacroCopyPhase {
    /// The phase's own comment: specific to it, unlike the build-setting paths it shares.
    static let signature = "compile the macOS executable transitively"
    /// Folders never holding a project the developer builds from.
    static let skipped = ProjectLayout.dependencyFolders
    static let maxDepth = 5

    /// Names of the generated projects in `project` that still have the phase.
    public static func projects(in project: Project) -> [String] {
        // Only Tuist generated the phase, and the walk over a large tree takes most of a second.
        let tuistFolders = project.layout(.anywhereButHome).tuistFolders
        guard !tuistFolders.isEmpty else { return [] }
        let derived = tuistFolders.flatMap { children(of: $0.appending(path: "Tuist/.build/tuist-derived/Projects")) }
        let candidates = projectFiles(under: project.root, depth: 0) + derived.flatMap { projectFiles(under: $0, depth: maxDepth - 1) }
        return candidates.filter(containsPhase).map {
            ($0.deletingLastPathComponent().lastPathComponent as NSString).deletingPathExtension
        }.sorted()
    }

    static func projectFiles(under folder: URL, depth: Int) -> [URL] {
        guard depth <= maxDepth else { return [] }
        return children(of: folder).flatMap { child -> [URL] in
            let name = child.lastPathComponent
            if name.hasSuffix(".xcodeproj") { return [child.appending(path: "project.pbxproj")] }
            guard !name.hasPrefix("."), !skipped.contains(name), isDirectory(child) else { return [] }
            return projectFiles(under: child, depth: depth + 1)
        }
    }

    static func containsPhase(_ file: URL) -> Bool {
        (try? String(contentsOf: file, encoding: .utf8))?.contains(signature) == true
    }

    static func children(of folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.sorted().map { folder.appending(path: $0) }
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
