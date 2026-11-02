import Foundation

/// Renders and reads `.mobilebuildmcp/config.yaml`. The format is MobileBuildMCP's; see its
/// configuration docs when a key changes.
public enum ConfigRenderer {
    /// Tool groups xcrew enables. `sim-env` is defined by `customWorkflows` below. Why the others are off is in
    /// docs/findings.md, *MobileBuildMCP's tool groups*.
    public static let workflows = ["simulator", "sim-env", "ui-automation", "debugging"]
    /// The tools of MobileBuildMCP's `simulator-management` group that `simulator` doesn't have.
    public static let simEnvTools = [
        "erase_sims", "set_sim_appearance", "set_sim_location", "reset_sim_location", "sim_statusbar",
        "toggle_software_keyboard", "toggle_connect_hardware_keyboard",
    ]

    public static func render(_ answers: ProfileAnswers, root: URL, simulatorIDs: [String: String] = [:], carried: CarriedDefaults = .init()) -> String {
        let pathKey = answers.container.hasSuffix(".xcodeproj") ? "projectPath" : "workspacePath"
        let location = quoted(relative(answers.container, to: root))

        func profile(_ name: String, scheme: String, simulator: String, extra: [String] = []) -> [String] {
            ["  \(name):", "    \(pathKey): \(location)", "    scheme: \(quoted(scheme))", "    simulatorName: \(quoted(simulator))"]
                + (simulatorIDs[simulator].map { ["    simulatorId: \(quoted($0))"] } ?? [])
                + extra + carried.relative(to: root).lines(for: name, indent: 4)
        }

        var lines = ["schemaVersion: 1", "enabledWorkflows:"] + workflows.map { "  - \($0)" }
        lines += ["customWorkflows:", "  sim-env:"] + simEnvTools.map { "    - \($0)" }
        lines += ["sentryDisabled: true", "showTestTiming: true"] + (answers.debuggerBackend.map { ["debuggerBackend: \($0)"] } ?? [])
        // In the order the active one is chosen: the first written is active.
        let bundle = answers.bundleID.map { ["    bundleId: \(quoted($0))"] } ?? []
        let written = answers.profileNames.map { name in
            switch name {
            case "unit": (name, profile(name, scheme: answers.testScheme ?? "", simulator: answers.testSimulator))
            case "app": (name, profile(name, scheme: answers.appScheme ?? "", simulator: answers.appSimulator, extra: bundle))
            default: (name, profile(name, scheme: answers.uiTestScheme ?? "", simulator: answers.appSimulator))
            }
        }
        if let active = written.first?.0 {
            lines += ["sessionDefaultsProfiles:"] + written.flatMap(\.1) + ["activeSessionDefaultsProfile: \(active)"]
        } else {
            lines += ["sessionDefaults:", "  \(pathKey): \(location)", "  simulatorName: \(quoted(answers.testSimulator))"]
                + (simulatorIDs[answers.testSimulator].map { ["  simulatorId: \(quoted($0))"] } ?? [])
                + carried.relative(to: root).lines(for: nil, indent: 2)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The profiles a config defines, in its order, which of them name a scheme, and the active one, as `sessions(in:)`
    /// reads them.
    public static func profiles(in yaml: String) -> (names: [String], withScheme: Set<String>, active: String?) {
        let profiles = sessions(in: yaml).profiles
        let withScheme = profiles.filter { entries($0.lines).contains { $0.key == "scheme" } }.map(\.name)
        return (profiles.map(\.name), Set(withScheme), topLevel("activeSessionDefaultsProfile", in: yaml))
    }

    /// The scheme MobileBuildMCP builds with when a call names none, by `hasSchemeToBuild`'s rule: the active profile's,
    /// or with none active, the global `sessionDefaults`'. With `profile`, that profile's, which stands alone. Nil when
    /// that has none.
    public static func schemeToBuild(in yaml: String, profile: String? = nil) -> String? {
        setting("scheme", profile: profile, in: yaml)
    }

    /// MobileBuildMCP's name for its global defaults when it reports the profile in use (`formatProfileLabel(null)`):
    /// the config's `sessionDefaults`.
    public static let globalProfile = "(default)"

    /// One of a profile's settings, by `schemeToBuild`'s rule; YAML's null and an empty value name none.
    public static func setting(_ key: String, profile named: String? = nil, in yaml: String) -> String? {
        let sessions = sessions(in: yaml)
        let block = { (name: String) in sessions.profiles.first { $0.name == name }?.lines }
        let lines: [String]?
        if named == globalProfile {
            lines = sessions.global
        } else if let named {
            lines = block(named)
        } else if let active = profiles(in: yaml).active {
            lines = block(active)
        } else {
            lines = sessions.global
        }
        return lines.flatMap { value(of: key, among: $0) }
    }

    /// Whether the config turns off MobileBuildMCP's following of Xcode's scheme selection after its start
    /// (`disableXcodeAutoSync: true` at the top level).
    public static func disablesXcodeAutoSync(in yaml: String) -> Bool {
        ["true", "True", "TRUE"].contains(topLevel("disableXcodeAutoSync", in: yaml) ?? "")
    }

    /// Whether MobileBuildMCP has a scheme to build with: the active profile's, since a named profile stands alone, or
    /// with none active, the global `sessionDefaults`' (docs/findings.md, *MobileBuildMCP's profiles*).
    public static func hasSchemeToBuild(in yaml: String) -> Bool {
        let profiles = profiles(in: yaml)
        if let active = profiles.active { return profiles.withScheme.contains(active) }
        return setting("scheme", profile: globalProfile, in: yaml) != nil
    }

    /// Every list a config holds, by the path of keys to it (`customWorkflows.sim-env`), block or flow style, at any
    /// indent, quoted or not, comments dropped. MobileBuildMCP writes the file back in its own style, so the doctor reads
    /// lists rather than matching setup's text.
    public static func lists(in yaml: String) -> [String: [String]] {
        var keys: [(indent: Int, key: String)] = []
        var lists: [String: [String]] = [:]
        func item(_ text: Substring) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            return unquoted(trimmed)
        }
        for raw in yaml.split(whereSeparator: \.isNewline) {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let indent = line.prefix { $0 == " " }.count
            if trimmed.hasPrefix("- ") || trimmed == "-" {
                // An item may sit at its key's own indent.
                while let last = keys.last, last.indent > indent { keys.removeLast() }
                lists[keys.map(\.key).joined(separator: "."), default: []].append(item(trimmed.dropFirst()))
            } else if let colon = trimmed.firstIndex(of: ":") {
                while let last = keys.last, last.indent >= indent { keys.removeLast() }
                keys.append((indent, item(trimmed[..<colon])))
                let value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("["), value.hasSuffix("]") {
                    lists[keys.map(\.key).joined(separator: "."), default: []] += value.dropFirst().dropLast().split(separator: ",").map(item)
                }
            }
        }
        return lists
    }

    /// Whether a config's tool groups are the ones setup writes now, in whatever order and layout.
    public static func hasCurrentToolGroups(_ lists: [String: [String]]) -> Bool {
        Set(lists["enabledWorkflows"] ?? []) == Set(workflows) && Set(lists["customWorkflows.sim-env"] ?? []) == Set(simEnvTools)
    }

    /// Whether any list in a config names MobileBuildMCP's `xcode-ide` group or one of its tools.
    public static func reachesXcodeIDE(_ lists: [String: [String]]) -> Bool {
        lists.values.joined().contains { $0 == "xcode-ide" || $0.hasPrefix("xcode_ide_") || $0.hasPrefix("xcode_tools_") }
    }

    /// The simulator IDs a config's profiles name, each once.
    public static func simulatorIDs(in yaml: String) -> [String] {
        values(of: ["simulatorId:"], in: yaml)
    }

    /// The debugger backend a config sets at its top level, which setup keeps when it writes the config again.
    public static func debuggerBackend(in yaml: String) -> String? {
        topLevel("debuggerBackend", in: yaml)
    }

    /// A config's top-level setting, read as `entries` reads a block; nil when it's null, empty or absent.
    static func topLevel(_ key: String, in yaml: String) -> String? {
        value(of: key, among: yaml.components(separatedBy: .newlines))
    }

    /// The simulator names a config's profiles reference, each once.
    public static func simulatorNames(in yaml: String) -> [String] {
        values(of: ["simulatorName:"], in: yaml)
    }

    static func values(of keys: [String], in yaml: String) -> [String] {
        let found = yaml.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let key = keys.first(where: trimmed.hasPrefix) else { return nil }
            return unquoted(trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces))
        }
        return Array(Set(found)).sorted()
    }

    /// The workspace and project paths a config's profiles point at, each once, as MobileBuildMCP resolves them: from
    /// the project root, its working directory, with `~` for the home folder (docs/findings.md, *MobileBuildMCP's config
    /// paths*).
    public static func containerPaths(in yaml: String, root: URL, home: URL) -> [String] {
        values(of: ["workspacePath:", "projectPath:"], in: yaml).map { resolved($0, root: root, home: home) }
    }

    /// A config's path as MobileBuildMCP resolves it: absolute as given, `~` for the home folder, else from the root.
    static func resolved(_ path: String, root: URL, home: URL) -> String {
        if path.hasPrefix("/") { return path }
        if path == "~" || path.hasPrefix("~/") { return home.appending(path: String(path.dropFirst(2))).path }
        return root.appending(path: path).standardizedFileURL.path
    }

    /// A path as the config writes it: from the project root (`./App.xcworkspace`) when it's inside it, else as given.
    static func relative(_ path: String, to root: URL) -> String {
        guard path.hasPrefix("/") else { return path.hasPrefix("./") ? path : "./" + path }
        // As given first, then as the file system spells both: a path that doesn't exist yet can't be resolved.
        for (full, base) in [(path, root.path), (ProjectLayout.canonicalPath(path), ProjectLayout.canonicalPath(root.path))] where full.hasPrefix(base + "/") {
            return "./" + full.dropFirst(base.count + 1)
        }
        return path
    }

    /// A YAML single-quoted scalar, so names with `: `, ` #` or quotes stay intact.
    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    /// The config without its session defaults, global or by profile, and the active profile's name: what only a
    /// restart loads into a running MobileBuildMCP.
    public static func serverPart(of yaml: String) -> String {
        let sessionKeys: Set<Substring> = ["sessionDefaults", "sessionDefaultsProfiles", "activeSessionDefaultsProfile"]
        var dropping = false
        var kept: [Substring] = []
        for line in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = line.first, first != " ", first != "\t", first != "-" {
                dropping = sessionKeys.contains(line.prefix { $0 != ":" })
            }
            if !dropping { kept.append(line) }
        }
        return kept.joined(separator: "\n")
    }

    /// A YAML scalar's text: single-quoted as xcrew writes it, double-quoted as a person may, or plain.
    static func unquoted(_ value: String) -> String {
        guard value.count >= 2, let quote = value.first, quote == "'" || quote == "\"", value.last == quote else { return value }
        let text = String(value.dropFirst().dropLast())
        return quote == "'" ? text.replacingOccurrences(of: "''", with: "'") : text
    }

    /// The keys MobileBuildMCP reads as paths (`utils/project-config.js`'s `pathKeys`), relative ones from its config's
    /// folder.
    static let pathKeys = ["projectPath", "workspacePath", "derivedDataPath"]

    /// `key`'s value on a config line (`  key: value`), quotes and a trailing comment taken off; nil on another key's
    /// line, and on a key with its value on the lines below.
    static func value(of key: String, in line: some StringProtocol) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\(key):") else { return nil }
        return scalar(trimmed.dropFirst(key.count + 1))?.value
    }
}
