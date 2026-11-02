import Foundation

/// The `session_set_defaults` calls that give a running MobileBuildMCP the session defaults a config holds, so a
/// session takes setup's profiles without a restart (MobileBuildMCP 2.7.1, `session_set_defaults.js`; its keys and their
/// types are `utils/session-defaults-schema.js`'s).
public enum LiveDefaults {
    /// One call a profile, as its tool's arguments in JSON, the active profile last, since each call makes its profile
    /// the session's; one call without a profile for global defaults. A path is made absolute from `root`, as
    /// MobileBuildMCP resolves the config's against its working directory.
    public static func calls(in yaml: String, root: URL) -> [String] {
        let sections = Self.sections(of: yaml)
        let active = ConfigRenderer.values(of: ["activeSessionDefaultsProfile:"], in: yaml).first
        var calls: [(name: String?, arguments: [String: Any])] = []
        for (name, lines) in sections.profiles {
            calls.append((name, ["profile": name, "createIfNotExists": true].merging(Self.defaults(lines, root: root)) { $1 }))
        }
        if calls.isEmpty, let global = sections.global { calls.append((nil, Self.defaults(global, root: root))) }
        let isActive = { (call: (name: String?, arguments: [String: Any])) in call.name != nil && call.name == active }
        let ordered = calls.filter { !isActive($0) } + calls.filter(isActive)
        return ordered.compactMap { call in
            (try? JSONSerialization.data(withJSONObject: call.arguments, options: [.sortedKeys, .withoutEscapingSlashes]))
                .map { "session_set_defaults " + String(decoding: $0, as: UTF8.self) }
        }
    }

    static let paths: Set<String> = ["projectPath", "workspacePath", "derivedDataPath"]

    /// The lines of `sessionDefaults`, and of each profile under `sessionDefaultsProfiles`, without their own indent.
    static func sections(of yaml: String) -> (global: [String]?, profiles: [(String, [String])]) {
        var global: [String]?
        var profiles: [(String, [String])] = []
        var section = ""
        var profileIndent: Int?
        for line in yaml.components(separatedBy: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
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
                if profileIndent == nil || indent <= profileIndent! {
                    profileIndent = indent
                    profiles.append((String(line.trimmingCharacters(in: .whitespaces).dropLast()), []))
                } else if !profiles.isEmpty {
                    profiles[profiles.count - 1].1.append(String(line.dropFirst(profileIndent! + 2)))
                }
            }
        }
        return (global, profiles)
    }

    /// One section's keys and values: a scalar as a string or a boolean, a list of strings, or a map of strings.
    static func defaults(_ lines: [String], root: URL) -> [String: Any] {
        var found: [String: Any] = [:]
        var key: String?
        for line in lines {
            if !line.hasPrefix(" ") {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                key = parts[0]
                guard parts.count == 2, !parts[1].isEmpty else { continue }
                let value = ConfigRenderer.unquoted(parts[1])
                if value == "true" || value == "false" {
                    found[parts[0]] = value == "true"
                } else {
                    found[parts[0]] = paths.contains(parts[0]) && !value.hasPrefix("/") ? root.appending(path: value).path : value
                }
            } else if let key {
                let item = line.trimmingCharacters(in: .whitespaces)
                if item.hasPrefix("- ") {
                    found[key] = ((found[key] as? [String]) ?? []) + [ConfigRenderer.unquoted(String(item.dropFirst(2)))]
                } else if let colon = item.firstIndex(of: ":") {
                    var map = (found[key] as? [String: String]) ?? [:]
                    map[String(item[..<colon])] = ConfigRenderer.unquoted(item[item.index(after: colon)...].trimmingCharacters(in: .whitespaces))
                    found[key] = map
                }
            }
        }
        return found
    }
}
