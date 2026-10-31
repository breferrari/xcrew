import Foundation

/// Which diagnostic groups are about concurrency, as an Xcode's own docs say: its toolchain ships one doc per group,
/// headed `# <title> (<Group>)` since Xcode 27, `# <title>` before, the file's name then giving the group. A group counts
/// when its doc speaks of concurrency or data races, or its title names `Sendable`, or when the words in its name say so:
/// a doc may say less than its name, and the docs add groups and titles but never take one away. A test pins the name
/// words to the installed docs (docs/findings.md, *Concurrency diagnostics*).
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
        let docs = files.filter { $0.pathExtension == "md" }.sorted { $0.path < $1.path }.compactMap { file -> (file: URL, text: String, title: Substring, group: Substring?)? in
            guard let text = try? String(contentsOf: file, encoding: .utf8),
                  let heading = text.firstMatch(of: #/^# (.+?)(?: \((\w+)\))?\s*$/#.anchorsMatchLineEndings()) else { return nil }
            return (file, text, heading.1, heading.2)
        }
        // Where headings name their group, one that doesn't is an index page; where none does, the file names the group.
        let headingsName = docs.contains { $0.group != nil }
        var groups = ConcurrencyGroups()
        for doc in docs {
            let group: String
            if let named = doc.group { group = String(named) } else if headingsName { continue } else {
                group = doc.file.deletingPathExtension().lastPathComponent.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
            }
            groups.documented.insert(group)
            let words = doc.text.lowercased()
            if words.contains("concurren") || words.contains("data race") || doc.title.contains("Sendable") { groups.titles[group] = String(doc.title) }
        }
        groups.isFromDocs = !groups.documented.isEmpty
        return groups
    }

    /// The words in a group's name that say it's about concurrency.
    static let nameWords = ["sendable", "sending", "isolat", "actor", "concurren", "datarace", "globalvariable"]

    /// Where the docs are in an Xcode: its default toolchain's `usr/share/doc/swift/diagnostics`.
    public static func docs(in xcode: URL) -> URL {
        xcode.appending(path: "Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/share/doc/swift/diagnostics")
    }

    /// Whether a diagnostic with these groups, outermost first, is about concurrency.
    func counts(_ groups: [String]) -> Bool {
        groups.contains { group in titles[group] != nil || Self.namesConcurrency(group) }
    }

    /// Whether a group's name says it's about concurrency.
    static func namesConcurrency(_ group: String) -> Bool {
        nameWords.contains { group.lowercased().contains($0) }
    }
}
