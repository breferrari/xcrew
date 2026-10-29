import Foundation

/// The specs an XcodeGen spec includes, which XcodeGen reads with it: an edit to any of them changes the project. A reader
/// of the top-level `include` key alone, in the forms XcodeGen's ProjectSpec documents, since the package takes no YAML
/// dependency; the rest of a spec is never read. Paths resolve as XcodeGen's `SpecFile` resolves them (docs/findings.md,
/// *XcodeGen's included specs*).
public enum XcodeGenSpec {
    /// One entry of `include`: a path, or an object with `relativePaths` and `enable`.
    public struct Include: Sendable, Equatable {
        let path: String
        var relativePaths = true
        var enable = true
    }

    /// Every spec XcodeGen reads for `spec`, itself included, at any depth, as standardized file URLs. Each is read
    /// once, so a cycle ends.
    static func files(from spec: URL) -> [URL] {
        // XcodeGen's loader keeps a base folder and a folder relative to it for each spec, and reads an include at the
        // base joined with its path.
        var found: [URL] = []
        var pending = [(base: spec.deletingLastPathComponent(), relative: "", path: spec.lastPathComponent)]
        while let next = pending.popLast() {
            let file = next.base.appending(path: next.path).standardizedFileURL
            guard !found.contains(file) else { continue }
            found.append(file)
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for include in includes(in: text) where include.enable {
                let base = include.relativePaths ? next.base.appending(path: next.relative) : next.base
                let relative = include.relativePaths ? (include.path as NSString).deletingLastPathComponent : ""
                pending.append((base, relative, include.path))
            }
        }
        return found
    }

    /// The entries of a spec's top-level `include` key: a path, a flow list of paths, or a block list of paths and
    /// objects. One that names a variable, which XcodeGen expands from the environment, or whose `enable` isn't a
    /// literal, is left out: xcrew can't know it at edit time.
    static func includes(in spec: String) -> [Include] {
        let lines = spec.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        guard let start = lines.firstIndex(where: { $0.hasPrefix("include:") }) else { return [] }
        let inline = scalar(String(lines[start].dropFirst("include:".count)))
        var entries: [[String: String]] = []
        if inline.hasPrefix("[") {
            entries = inline.dropFirst().prefix { $0 != "]" }.split(separator: ",").map { ["path": scalar(String($0))] }
        } else if !inline.isEmpty {
            entries = [["path": inline]]
        } else {
            // The list runs while lines are indented; each `- ` starts an entry, and deeper `key: value` lines add to it.
            for line in lines[(start + 1)...] {
                let content = line.trimmingCharacters(in: .whitespaces)
                if content.isEmpty || content.hasPrefix("#") { continue }
                guard line.first?.isWhitespace == true else { break }
                var field = content
                if content.hasPrefix("- ") {
                    entries.append([:])
                    field = String(content.dropFirst(2))
                }
                guard !entries.isEmpty else { continue }
                if let colon = field.range(of: ": ") ?? (field.hasSuffix(":") ? field.range(of: ":", options: .backwards) : nil) {
                    entries[entries.count - 1][String(field[..<colon.lowerBound])] = scalar(String(field[colon.upperBound...]))
                } else {
                    entries[entries.count - 1]["path"] = scalar(field)
                }
            }
        }
        return entries.compactMap { entry in
            guard let path = entry["path"], !path.isEmpty, !path.contains("${") else { return nil }
            guard let relativePaths = flag(entry["relativePaths"]), let enable = flag(entry["enable"]) else { return nil }
            return Include(path: path, relativePaths: relativePaths, enable: enable)
        }
    }

    /// A YAML scalar without its comment or quotes.
    static func scalar(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespaces)
        if let quote = value.first, quote == "\"" || quote == "'", let end = value.dropFirst().firstIndex(of: quote) {
            return String(value[value.index(after: value.startIndex)..<end])
        }
        if let comment = value.range(of: " #") { value = String(value[..<comment.lowerBound]) }
        return value.trimmingCharacters(in: .whitespaces)
    }

    /// An include's flag: true when absent, as both default, and nothing when it isn't a literal, such as a variable.
    static func flag(_ value: String?) -> Bool? {
        switch value?.lowercased() {
        case nil, "true", "yes": true
        case "false", "no": false
        default: nil
        }
    }
}
