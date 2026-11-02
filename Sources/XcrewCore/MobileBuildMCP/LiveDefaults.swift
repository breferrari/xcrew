import Foundation

/// The `session_set_defaults` calls that give a running MobileBuildMCP the session defaults a config holds, so a
/// session takes setup's profiles without a restart (MobileBuildMCP 2.7.1, `session_set_defaults.js`; its keys and their
/// types are `utils/session-defaults-schema.js`'s).
public enum LiveDefaults {
    /// One call a profile, as its tool's arguments in JSON, the active profile last, since each call makes its profile
    /// the session's; one call without a profile for global defaults. A path is made absolute as MobileBuildMCP resolves
    /// the config's against its working directory, `root`, standardized, with `~` for `home`.
    public static func calls(in yaml: String, root: URL, home: URL) -> [String] {
        let sessions = ConfigRenderer.sessions(in: yaml)
        let active = ConfigRenderer.profiles(in: yaml).active
        var calls: [(name: String?, arguments: [String: Any])] = []
        for (name, lines) in sessions.profiles {
            calls.append((name, ["profile": name, "createIfNotExists": true].merging(Self.defaults(lines, root: root, home: home)) { $1 }))
        }
        if calls.isEmpty, let global = sessions.global { calls.append((nil, Self.defaults(global, root: root, home: home))) }
        let isActive = { (call: (name: String?, arguments: [String: Any])) in call.name != nil && call.name == active }
        let ordered = calls.filter { !isActive($0) } + calls.filter(isActive)
        return ordered.compactMap { call in
            (try? JSONSerialization.data(withJSONObject: call.arguments, options: [.sortedKeys, .withoutEscapingSlashes]))
                .map { "session_set_defaults " + String(decoding: $0, as: UTF8.self) }
        }
    }

    /// One block's keys and values, as YAML reads them: a scalar as a string, or a boolean when it's a plain `true` or
    /// `false`; a list of strings, inline or one item a line, at the key's indent or below it; a map of strings, inline
    /// or one entry a line; a value wrapped onto the lines below folded with one space. Null and empty values are left
    /// out. A path resolves as MobileBuildMCP resolves the config's (`ConfigRenderer.resolved`).
    static func defaults(_ lines: [String], root: URL, home: URL) -> [String: Any] {
        var found: [String: Any] = [:]
        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            guard !line.hasPrefix(" "), !line.hasPrefix("-"), let name = ConfigRenderer.key(of: line) else { continue }
            var rest = ConfigRenderer.rest(of: line)
            var below: [String] = []
            while index < lines.count, lines[index].hasPrefix(" ") || (rest.isEmpty && lines[index].hasPrefix("- ")) {
                below.append(lines[index].trimmingCharacters(in: .whitespaces))
                index += 1
            }
            if !rest.isEmpty {
                rest = ([rest] + below).joined(separator: " ")
                guard let scalar = ConfigRenderer.scalar(rest), !ConfigRenderer.isNull(scalar) else { continue }
                if !scalar.isQuoted, let items = ConfigRenderer.inlineItems(scalar.value, open: "[", close: "]") {
                    found[name] = items.compactMap { ConfigRenderer.scalar($0)?.value }
                } else if !scalar.isQuoted, let entries = ConfigRenderer.inlineItems(scalar.value, open: "{", close: "}") {
                    found[name] = Self.map(entries)
                } else if !scalar.isQuoted, let flag = ["true": true, "True": true, "TRUE": true, "false": false, "False": false, "FALSE": false][scalar.value] {
                    found[name] = flag
                } else {
                    found[name] = ConfigRenderer.pathKeys.contains(name) ? ConfigRenderer.resolved(scalar.value, root: root, home: home) : scalar.value
                }
            } else if below.first?.hasPrefix("- ") == true {
                found[name] = below.filter { $0.hasPrefix("- ") }.compactMap { ConfigRenderer.scalar($0.dropFirst(2))?.value }
            } else if !below.isEmpty {
                found[name] = Self.map(below)
            }
        }
        return found
    }

    /// A map's entries, `KEY: value` each, as strings.
    static func map(_ entries: [String]) -> [String: String] {
        Dictionary(entries.compactMap { entry in ConfigRenderer.key(of: entry).map { ($0, ConfigRenderer.scalar(ConfigRenderer.rest(of: entry))?.value ?? "") } }) { first, _ in first }
    }
}
