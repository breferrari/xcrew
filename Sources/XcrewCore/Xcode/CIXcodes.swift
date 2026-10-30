import Foundation

/// The Xcode versions a project's CI names. Only GitHub Actions' workflows are read: Xcode Cloud, Bitrise, CircleCI and
/// other CI systems are out of scope (docs/findings.md, *Which Xcode*).
public enum CIXcodes {
    /// An Xcode version a workflow names, and where.
    public struct Named: Sendable, Equatable {
        public let file: String
        public let line: Int
        public let version: String
    }

    /// Each version the workflows name: setup-xcode's `xcode-version`, an `xcode-select -s` or `--switch` to an app, a
    /// `DEVELOPER_DIR` inside one, and a pin file a line reads to choose its Xcode. One that picks the newest, or a range,
    /// names no version to compare and isn't listed.
    public static func named(in project: Project) -> [Named] {
        // A pin file holds one version; anything else names none to compare.
        let pinned = { (path: String) in project.pinned(at: path).flatMap { $0.wholeMatch(of: /\d+(?:\.\d+)*/).map { String($0.output) } } }
        let folder = project.root.appending(path: ".github/workflows")
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".yml") || $0.hasSuffix(".yaml") }.sorted()
        return files.flatMap { name in
            let text = (try? String(contentsOf: folder.appending(path: name), encoding: .utf8)) ?? ""
            return text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { index, line in
                version(in: String(line), pinned: pinned).map { Named(file: ".github/workflows/\(name)", line: index + 1, version: $0) }
            }
        }
    }

    /// Whether a version CI names covers `ours`: its parts begin ours, as setup-xcode reads `26` as the newest 26.x, and a
    /// missing part counts as zero.
    public static func covers(_ named: String, _ ours: String) -> Bool {
        let wanted = Version(named).parts
        let have = Version(ours).parts + Array(repeating: 0, count: wanted.count)
        return Array(have.prefix(wanted.count)) == wanted
    }

    /// The version a workflow line names, past any YAML comment, which is an old setup's: written out, or in the pin file
    /// it reads, as `pinned` reads a path from the project's root.
    static func version(in written: String, pinned: (String) -> String? = { _ in nil }) -> String? {
        let line = code(of: written)
        if let input = line.firstMatch(of: /xcode-version:\s*['"]?(\d+(?:\.\d+)*)(?=['"\s#]|$)/) { return String(input.1) }
        if let path = pinRead(by: line), let version = pinned(path) { return version }
        guard line.contains("xcode-select") || line.contains("DEVELOPER_DIR") else { return nil }
        return line.firstMatch(of: /Xcode[_-]?(\d+(?:\.\d+)*)[^\/\s]*\.app/).map { String($0.1) }
    }

    /// The pin file a workflow line reads to choose an Xcode, from the project's root: an action's `xcode-version-file`,
    /// `xcodes select` or `install` given no version, which read the pin in the current folder (xcodes' `select` help and
    /// its install's version-file lookup, docs/findings.md), or `cat` or `<` of it on a line that selects an Xcode, assigns
    /// what it read, or adds it to `$GITHUB_ENV`. Printing or checking it, hashing it for a cache key, or a path filter,
    /// chooses nothing.
    static func pinRead(by line: String) -> String? {
        if let input = line.firstMatch(of: /xcode-version-file:\s*["']?(?:\.\/)?([^\s"'#]+)/) { return String(input.1) }
        if line.contains(/\bxcodes\s+(?:select|install)\b(?!\s+["']?\d)/) { return Project.xcodePinFile }
        guard line.contains(/xcode-select|DEVELOPER_DIR|\w+=\$\(|GITHUB_ENV/),
              let read = line.firstMatch(of: /(?:\bcat\s+|<\s*)["']?(?:\.\/)?([\w.\/-]*\.xcode-version)(?=["'\s)]|$)/)
        else { return nil }
        return String(read.1)
    }

    /// A line without its comment: from a `#` that starts it or follows a space.
    static func code(of line: String) -> String {
        var previous: Character = " "
        for index in line.indices {
            if line[index] == "#", previous.isWhitespace { return String(line[..<index]) }
            previous = line[index]
        }
        return line
    }
}
