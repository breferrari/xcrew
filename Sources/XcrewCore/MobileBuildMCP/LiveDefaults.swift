import Foundation

/// The `session_set_defaults` calls that give a running MobileBuildMCP the session defaults a config holds, so a
/// session takes setup's profiles without a restart (MobileBuildMCP 2.7.1, `session_set_defaults.js`; its keys and their
/// types are `utils/session-defaults-schema.js`'s).
public enum LiveDefaults {
    /// One call a profile, as its tool's arguments in JSON, the active profile last, since each call makes its profile
    /// the session's; one call without a profile for global defaults. A path is made absolute as MobileBuildMCP resolves
    /// the config's against its working directory, `root`, standardized, with `~` for `home`.
    public static func calls(in yaml: String, root: URL, home: URL) -> [String] {
        let sections = Self.sections(of: yaml)
        let active = ConfigRenderer.profiles(in: yaml).active
        var calls: [(name: String?, arguments: [String: Any])] = []
        for (name, lines) in sections.profiles {
            calls.append((name, ["profile": name, "createIfNotExists": true].merging(Self.defaults(lines, root: root, home: home)) { $1 }))
        }
        if calls.isEmpty, let global = sections.global { calls.append((nil, Self.defaults(global, root: root, home: home))) }
        let isActive = { (call: (name: String?, arguments: [String: Any])) in call.name != nil && call.name == active }
        let ordered = calls.filter { !isActive($0) } + calls.filter(isActive)
        return ordered.compactMap { call in
            (try? JSONSerialization.data(withJSONObject: call.arguments, options: [.sortedKeys, .withoutEscapingSlashes]))
                .map { "session_set_defaults " + String(decoding: $0, as: UTF8.self) }
        }
    }

    /// The lines of `sessionDefaults`, and of each profile under `sessionDefaultsProfiles` by its unquoted name, without
    /// their own indent, as `ConfigRenderer.profiles` reads the sections: a comment or blank line ends none.
    static func sections(of yaml: String) -> (global: [String]?, profiles: [(String, [String])]) {
        var global: [String]?
        var profiles: [(String, [String])] = []
        var section = ""
        var profileIndent: Int?
        for line in yaml.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = line.prefix { $0 == " " }.count
            if indent == 0 {
                section = String(line.prefix { $0 != ":" })
                profileIndent = nil
                if section == "sessionDefaults" { global = [] }
                continue
            }
            if section == "sessionDefaults" {
                global?.append(String(line.dropFirst(min(indent, 2))))
            } else if section == "sessionDefaultsProfiles" {
                if profileIndent == nil || indent <= profileIndent ?? 0 {
                    profileIndent = indent
                    profiles.append((ConfigRenderer.unquoted(String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)), []))
                } else if !profiles.isEmpty {
                    profiles[profiles.count - 1].1.append(String(line.dropFirst((profileIndent ?? 0) + 2)))
                }
            }
        }
        return (global, profiles)
    }

    /// One section's keys and values, each read as `ConfigRenderer.value(of:in:)` reads a config line, quotes and a
    /// trailing comment taken off: a scalar as a string or a boolean, a list of strings, or a map of strings. A path
    /// resolves as MobileBuildMCP resolves the config's (`ConfigRenderer.resolved`).
    static func defaults(_ lines: [String], root: URL, home: URL) -> [String: Any] {
        var found: [String: Any] = [:]
        var key: String?
        for line in lines {
            if !line.hasPrefix(" ") {
                let name = String(line.prefix { $0 != ":" }).trimmingCharacters(in: .whitespaces)
                key = name
                guard let value = ConfigRenderer.value(of: name, in: line) else { continue }
                if value == "true" || value == "false" {
                    found[name] = value == "true"
                } else {
                    found[name] = ConfigRenderer.pathKeys.contains(name) ? ConfigRenderer.resolved(value, root: root, home: home) : value
                }
            } else if let key {
                let item = line.trimmingCharacters(in: .whitespaces)
                if item.hasPrefix("- "), let value = ConfigRenderer.value(of: "-", in: "-: " + item.dropFirst(2)) {
                    found[key] = ((found[key] as? [String]) ?? []) + [value]
                } else if let colon = item.firstIndex(of: ":") {
                    let name = String(item[..<colon])
                    var map = (found[key] as? [String: String]) ?? [:]
                    map[name] = ConfigRenderer.value(of: name, in: item) ?? ""
                    found[key] = map
                }
            }
        }
        return found
    }
}
