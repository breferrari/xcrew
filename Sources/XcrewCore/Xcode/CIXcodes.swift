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

    /// Each version the workflows name: setup-xcode's `xcode-version`, an `xcode-select -s` or `--switch` to an app, and a
    /// `DEVELOPER_DIR` inside one. One that picks the newest, or a range, names no version to compare and isn't listed.
    public static func named(in project: Project) -> [Named] {
        let folder = project.root.appending(path: ".github/workflows")
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".yml") || $0.hasSuffix(".yaml") }.sorted()
        return files.flatMap { name in
            let text = (try? String(contentsOf: folder.appending(path: name), encoding: .utf8)) ?? ""
            return text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { index, line in
                version(in: String(line)).map { Named(file: ".github/workflows/\(name)", line: index + 1, version: $0) }
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

    /// The version a workflow line names, past any YAML comment, which is an old setup's.
    static func version(in written: String) -> String? {
        let line = code(of: written)
        if let input = line.firstMatch(of: /xcode-version:\s*['"]?(\d+(?:\.\d+)*)(?=['"\s#]|$)/) { return String(input.1) }
        guard line.contains("xcode-select") || line.contains("DEVELOPER_DIR") else { return nil }
        return line.firstMatch(of: /Xcode[_-]?(\d+(?:\.\d+)*)[^\/\s]*\.app/).map { String($0.1) }
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
