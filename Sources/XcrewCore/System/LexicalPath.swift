/// A path with `.`, `..` and empty parts resolved by its words alone, the file system unasked: `standardizedFileURL`
/// would also drop `/private` from `/private/var`, while the paths it's matched against keep it.
enum LexicalPath {
    /// `path`, absolute, in that one spelling; a `..` past the root stays at the root.
    static func of(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/") where part != "." {
            if part == ".." { _ = parts.popLast() } else { parts.append(part) }
        }
        return "/" + parts.joined(separator: "/")
    }
}
