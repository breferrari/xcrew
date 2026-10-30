import Foundation

/// Which diagnostic groups are about concurrency, as the selected Xcode's own docs say: its toolchain ships one doc per
/// group, `# <title> (<Group>)`, and a group counts when its doc speaks of concurrency or data races, or its title names
/// `Sendable`. A group with no doc goes by the words in its name, which a test pins to the installed docs
/// (docs/findings.md, *Concurrency diagnostics*).
public struct ConcurrencyGroups: Sendable, Equatable {
    /// Each concurrency group the docs name, with its doc's title.
    public var titles: [String: String] = [:]
    /// Whether the docs were read, rather than the names alone.
    public var isFromDocs = false
    /// Every group the docs have a doc for, about concurrency or not.
    var documented: Set<String> = []

    /// The groups the docs folder names, or the name rule alone when there's no folder.
    public static func read(docs folder: URL?) -> ConcurrencyGroups {
        guard let folder, let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return ConcurrencyGroups() }
        var groups = ConcurrencyGroups()
        for file in files where file.pathExtension == "md" {
            guard let text = try? String(contentsOf: file, encoding: .utf8),
                  let heading = text.firstMatch(of: #/^# (.+) \((\w+)\)\s*$/#.anchorsMatchLineEndings()) else { continue }
            let group = String(heading.2)
            groups.documented.insert(group)
            // Its body speaks of concurrency or data races, or its title names `Sendable`: an example's code may hold a
            // `Sendable` of no concern to the group.
            let words = text.lowercased()
            if words.contains("concurren") || words.contains("data race") || heading.1.contains("Sendable") { groups.titles[group] = String(heading.1) }
        }
        groups.isFromDocs = !groups.documented.isEmpty
        return groups
    }

    /// The words in a group's name that say it's about concurrency, for a group no doc speaks for.
    static let nameWords = ["sendable", "sending", "isolat", "actor", "concurren", "datarace", "globalvariable"]

    /// Where the docs are in an Xcode: its default toolchain's `usr/share/doc/swift/diagnostics`.
    public static func docs(in xcode: URL) -> URL {
        xcode.appending(path: "Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/share/doc/swift/diagnostics")
    }

    /// Whether a diagnostic with these groups, outermost first, is about concurrency.
    func counts(_ groups: [String]) -> Bool {
        groups.contains { group in
            if titles[group] != nil { return true }
            if documented.contains(group) { return false }
            return Self.nameWords.contains { group.lowercased().contains($0) }
        }
    }
}
