import Foundation

/// The session defaults an existing config holds that setup doesn't set itself, such as `derivedDataPath` or `env`, kept
/// when setup writes over it. A named profile stands alone in MobileBuildMCP (docs/findings.md, *MobileBuildMCP's
/// profiles*), so the global ones go into each profile, under the profile's own of the same name.
public struct CarriedDefaults: Sendable, Equatable {
    /// A key and its value as the file wrote it: the key's line, then any lines nested under it, from the key's indent.
    struct Entry: Sendable, Equatable {
        let key: String
        let lines: [String]
    }

    /// The keys setup writes from its answers.
    static let setByXcrew: Set<String> = ["workspacePath", "projectPath", "scheme", "simulatorName", "simulatorId", "bundleId"]

    var global: [Entry] = []
    var profiles: [String: [Entry]] = [:]

    public init() {}

    public init(_ yaml: String) {
        var section: String?
        var profile: String?
        var profileIndent: Int?
        var keyIndent: Int?
        var current: (key: String, indent: Int, lines: [String], profile: String?)?
        func flush() {
            guard let entry = current else { return }
            current = nil
            guard !Self.setByXcrew.contains(entry.key) else { return }
            if let name = entry.profile { profiles[name, default: []].append(Entry(key: entry.key, lines: entry.lines)) } else { global.append(Entry(key: entry.key, lines: entry.lines)) }
        }
        for raw in yaml.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = line.prefix { $0 == " " }.count
            if let entry = current, indent > entry.indent {
                current?.lines.append(String(repeating: " ", count: indent - entry.indent) + trimmed)
                continue
            }
            flush()
            if indent == 0 {
                section = String(trimmed.prefix { $0 != ":" })
                (profile, profileIndent, keyIndent) = (nil, nil, nil)
                continue
            }
            let key = String(trimmed.prefix { $0 != ":" })
            switch section {
            case "sessionDefaults":
                current = (key, indent, [trimmed], nil)
            case "sessionDefaultsProfiles":
                if profileIndent == nil || indent == profileIndent {
                    (profile, profileIndent, keyIndent) = (ConfigRenderer.unquoted(key), indent, nil)
                } else if let name = profile {
                    if keyIndent == nil { keyIndent = indent }
                    if indent == keyIndent { current = (key, indent, [trimmed], name) }
                }
            default:
                break
            }
        }
        flush()
    }

    /// What a profile gets, or with `profile` nil the global defaults: the global entries, each replaced by the profile's
    /// own of the same key, then the profile's others.
    func entries(for profile: String?) -> [Entry] {
        let own = profile.flatMap { profiles[$0] } ?? []
        let ownKeys = Set(own.map(\.key))
        return global.filter { !ownKeys.contains($0.key) } + own
    }

    /// The lines for a profile's or the global defaults' block, at `indent`.
    func lines(for profile: String?, indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        return entries(for: profile).flatMap(\.lines).map { pad + $0 }
    }

    /// The keys carried into the profiles setup writes, each once, in order.
    public func keys(for written: [String]) -> [String] {
        Array(Set((written.isEmpty ? [nil] : written.map(Optional.some)).flatMap { entries(for: $0).map(\.key) })).sorted()
    }
}
