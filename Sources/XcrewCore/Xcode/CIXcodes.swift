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
        let patterns = Patterns()
        // Each workflow, then each local action one uses, as `uses: ./path` names it from the root, read once.
        var queue = files.map { ".github/workflows/\($0)" }
        var read: Set<String> = []
        var named: [Named] = []
        while !queue.isEmpty {
            let file = queue.removeFirst()
            guard read.insert(file).inserted, let text = try? String(contentsOf: project.root.appending(path: file), encoding: .utf8) else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if let version = version(in: String(line), pinned: pinned, patterns: patterns) { named.append(Named(file: file, line: index + 1, version: version)) }
                if let action = localAction(usedBy: String(line), in: project, patterns: patterns) { queue.append(action) }
            }
        }
        return named
    }

    /// The `action.yml` (or `action.yaml`) of the local action a workflow line uses, `uses: ./.github/actions/setup`, from
    /// the project's root, as GitHub resolves it; nil for any other line, or an action outside the project.
    static func localAction(usedBy written: String, in project: Project, patterns: Patterns = Patterns()) -> String? {
        guard let used = code(of: written).firstMatch(of: patterns.localUses).map({ String($0.1) }),
              !used.split(separator: "/").contains("..") else { return nil }
        let folder = used.hasSuffix("/") ? String(used.dropLast()) : used
        return ["action.yml", "action.yaml"].map { "\(folder)/\($0)" }.first { FileManager.default.fileExists(atPath: project.root.appending(path: $0).path) }
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
    static func version(in written: String, pinned: (String) -> String? = { _ in nil }, patterns: Patterns = Patterns()) -> String? {
        let line = code(of: written)
        if let input = line.firstMatch(of: patterns.versionInput) { return String(input.1) }
        if let path = pinRead(by: line, patterns: patterns), let version = pinned(path) { return version }
        guard line.contains("xcode-select") || line.contains("DEVELOPER_DIR") else { return nil }
        return line.firstMatch(of: patterns.app).map { String($0.1) }
    }

    /// The pin file a workflow line reads to choose an Xcode, from the project's root: an action's `xcode-version-file`,
    /// `xcodes select` or `install` given no version, which read the pin in the current folder (xcodes' `select` help and
    /// its install's version-file lookup, docs/findings.md), or `cat` or `<` of it on a line that selects an Xcode, assigns
    /// what it read, or adds it to `$GITHUB_ENV`. Printing or checking it, hashing it for a cache key, or a path filter,
    /// chooses nothing.
    static func pinRead(by line: String, patterns: Patterns = Patterns()) -> String? {
        if let input = line.firstMatch(of: patterns.versionFile) { return String(input.1) }
        if line.contains(patterns.xcodesReadingPin) { return Project.xcodePinFile }
        guard line.contains(patterns.choosing), let read = line.firstMatch(of: patterns.pinFileRead) else { return nil }
        return String(read.1)
    }

    /// The expressions a workflow line is read with, made once per scan: a regular expression literal is compiled each time
    /// it's evaluated, and a scan reads every line of every workflow.
    struct Patterns {
        let versionInput = /xcode-version:\s*['"]?(\d+(?:\.\d+)*)(?=['"\s#]|$)/
        let app = /Xcode[_-]?(\d+(?:\.\d+)*)[^\/\s]*\.app/
        let versionFile = /xcode-version-file:\s*["']?(?:\.\/)?([^\s"'#]+)/
        // A version or an input passed through, `'${{ inputs.xcode-version }}'`, isn't the pin file.
        let xcodesReadingPin = /\bxcodes\s+(?:select|install)\b(?!\s+["']?[\d$])/
        let localUses = /uses:\s*["']?\.\/([^\s"'#@]+)/
        let choosing = /xcode-select|DEVELOPER_DIR|\w+=\$\(|GITHUB_ENV/
        let pinFileRead = /(?:\bcat\s+|<\s*)["']?(?:\.\/)?([\w.\/-]*\.xcode-version)(?=["'\s)]|$)/
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
