import Foundation

/// The session defaults an existing config holds that setup doesn't set itself, such as `derivedDataPath` or `env`, kept
/// when setup writes over it. A named profile stands alone in MobileBuildMCP (docs/findings.md, *MobileBuildMCP's
/// profiles*), so each profile setup writes gets them all: its own of the same name first, then the global ones, then
/// any other profile's, by the first that names a key.
public struct CarriedDefaults: Sendable, Equatable {
    /// A key and its value as the file wrote it: the key's line, then the lines under it, from the key's indent.
    struct Entry: Sendable, Equatable {
        let key: String
        var lines: [String]
    }

    /// The keys `ConfigRenderer.render` writes into a profile, and into the global defaults when it writes no profile.
    static let setInProfiles: Set<String> = ["workspacePath", "projectPath", "scheme", "simulatorName", "simulatorId", "bundleId"]
    static let setGlobally: Set<String> = ["workspacePath", "projectPath", "simulatorName", "simulatorId"]

    var global: [Entry] = []
    var profiles: [String: [Entry]] = [:]
    /// The profiles in the order the file names them.
    var profileOrder: [String] = []

    public init() {}

    public init(_ yaml: String) {
        var section: String?
        var profile: String?
        var profileIndent: Int?
        var keyIndent: Int?
        var current: (entry: Entry, indent: Int, profile: String?)?
        func flush() {
            guard let (entry, _, name) = current else { return }
            current = nil
            let kept = Entry(key: entry.key, lines: Array(entry.lines.reversed().drop { $0.isEmpty }.reversed()))
            if let name { profiles[name, default: []].append(kept) } else { global.append(kept) }
        }
        for raw in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix { $0 == " " }.count
            // A value runs on through deeper lines, blank ones, and list items at its key's own indent.
            if let (_, keyAt, _) = current, trimmed.isEmpty || indent > keyAt || (indent == keyAt && trimmed.hasPrefix("-")) {
                current?.entry.lines.append(trimmed.isEmpty ? "" : String(repeating: " ", count: indent - keyAt) + trimmed)
                continue
            }
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            flush()
            let key = ConfigRenderer.unquoted(String(trimmed.prefix { $0 != ":" }))
            if indent == 0 {
                (section, profile, profileIndent, keyIndent) = (key, nil, nil, nil)
                continue
            }
            switch section {
            case "sessionDefaults":
                current = (Entry(key: key, lines: [trimmed]), indent, nil)
            case "sessionDefaultsProfiles":
                if profileIndent == nil || indent == profileIndent {
                    (profile, profileIndent, keyIndent) = (key, indent, nil)
                    profileOrder.append(key)
                } else if let profile {
                    if keyIndent == nil { keyIndent = indent }
                    if indent == keyIndent { current = (Entry(key: key, lines: [trimmed]), indent, profile) }
                }
            default:
                break
            }
        }
        flush()
    }

    /// What a profile setup writes gets, or with `profile` nil the global defaults, leaving out what setup sets there.
    func entries(for profile: String?) -> [Entry] {
        let skipped = profile == nil ? Self.setGlobally : Self.setInProfiles
        let others = profileOrder.filter { $0 != profile }.map { profiles[$0] ?? [] }
        var seen: Set<String> = []
        return ([profile.flatMap { profiles[$0] } ?? [], global] + others).joined().filter { !skipped.contains($0.key) && seen.insert($0.key).inserted }
    }

    /// The lines for a profile's or the global defaults' block, at `indent`.
    func lines(for profile: String?, indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        return entries(for: profile).flatMap(\.lines).map { $0.isEmpty ? "" : pad + $0 }
    }

    /// The simulator a profile names, or with `profile` nil the global defaults' one.
    public func simulatorName(of profile: String?) -> String? {
        let entries = profile.map { profiles[$0] ?? [] } ?? global
        return entries.first { $0.key == "simulatorName" }.flatMap(\.lines.first).map { line in
            ConfigRenderer.unquoted(line.dropFirst("simulatorName:".count).trimmingCharacters(in: .whitespaces))
        }
    }

    /// The keys carried into the profiles setup writes, or into the global defaults when it writes none, sorted.
    public func keys(for written: [String]) -> [String] {
        let blocks: [String?] = written.isEmpty ? [nil] : written
        return Set(blocks.flatMap { entries(for: $0).map(\.key) }).sorted()
    }
}
