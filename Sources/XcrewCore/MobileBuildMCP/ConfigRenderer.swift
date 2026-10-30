import Foundation

/// Renders and reads `.mobilebuildmcp/config.yaml`. The format is MobileBuildMCP's; see its
/// configuration docs when a key changes.
public enum ConfigRenderer {
    /// Tool groups xcrew enables. `sim-env` is defined by `customWorkflows` below.
    public static let workflows = ["simulator", "sim-env", "xcode-ide", "ui-automation", "debugging"]
    /// Simulator-environment tools from MobileBuildMCP's `simulator-management` group, without
    /// the ones `simulator` already has.
    public static let simEnvTools = [
        "erase_sims", "set_sim_appearance", "set_sim_location", "reset_sim_location",
        "toggle_software_keyboard", "toggle_connect_hardware_keyboard",
    ]

    public static func render(_ answers: ProfileAnswers, root: URL, simulatorIDs: [String: String] = [:]) -> String {
        let pathKey = answers.container.hasSuffix(".xcodeproj") ? "projectPath" : "workspacePath"
        let location = quoted(root.appending(path: answers.container).path)

        func profile(_ name: String, scheme: String, simulator: String, extra: [String] = []) -> [String] {
            ["  \(name):", "    \(pathKey): \(location)", "    scheme: \(quoted(scheme))", "    simulatorName: \(quoted(simulator))"]
                + (simulatorIDs[simulator].map { ["    simulatorId: \(quoted($0))"] } ?? [])
                + extra
        }

        var lines = ["schemaVersion: 1", "enabledWorkflows:"] + workflows.map { "  - \($0)" }
        lines += ["customWorkflows:", "  sim-env:"] + simEnvTools.map { "    - \($0)" }
        lines += ["sentryDisabled: true", "showTestTiming: true"]
        // In the order the active one is chosen: the first written is active.
        let bundle = answers.bundleID.map { ["    bundleId: \(quoted($0))"] } ?? []
        let written = [
            ("unit", answers.testScheme, answers.testSimulator, [String]()),
            ("app", answers.appScheme, answers.appSimulator, bundle),
            ("ui", answers.uiTestScheme, answers.appSimulator, []),
        ].compactMap { name, scheme, simulator, extra in scheme.map { (name, profile(name, scheme: $0, simulator: simulator, extra: extra)) } }
        if let active = written.first?.0 {
            lines += ["sessionDefaultsProfiles:"] + written.flatMap(\.1) + ["activeSessionDefaultsProfile: \(active)"]
        } else {
            lines += ["sessionDefaults:", "  \(pathKey): \(location)", "  simulatorName: \(quoted(answers.testSimulator))"]
                + (simulatorIDs[answers.testSimulator].map { ["  simulatorId: \(quoted($0))"] } ?? [])
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The profiles a config defines, in its order, which of them name a scheme, and the active one. A
    /// profile is a key one level inside `sessionDefaultsProfiles`, at whatever indent the file uses.
    public static func profiles(in yaml: String) -> (names: [String], withScheme: Set<String>, active: String?) {
        var names: [String] = []
        var withScheme: Set<String> = []
        var inProfiles = false
        var keyIndent: Int?
        for raw in yaml.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = line.prefix { $0 == " " }.count
            if indent == 0 {
                inProfiles = trimmed == "sessionDefaultsProfiles:"
                keyIndent = nil
                continue
            }
            guard inProfiles else { continue }
            if keyIndent == nil { keyIndent = indent }
            if indent == keyIndent, trimmed.hasSuffix(":") {
                names.append(unquoted(trimmed.dropLast().trimmingCharacters(in: .whitespaces)))
            } else if indent > keyIndent ?? 0, trimmed.hasPrefix("scheme:"), let current = names.last {
                withScheme.insert(current)
            }
        }
        return (names, withScheme, values(of: ["activeSessionDefaultsProfile:"], in: yaml).first)
    }

    /// Whether MobileBuildMCP has a scheme to build with: the active profile's, since a named profile stands alone, or
    /// with none active, the global `sessionDefaults`' (docs/findings.md, *MobileBuildMCP's profiles*).
    public static func hasSchemeToBuild(in yaml: String) -> Bool {
        let profiles = profiles(in: yaml)
        if let active = profiles.active { return profiles.withScheme.contains(active) }
        var inDefaults = false
        for raw in yaml.split(whereSeparator: \.isNewline) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if !raw.hasPrefix(" ") {
                inDefaults = trimmed == "sessionDefaults:"
            } else if inDefaults, trimmed.hasPrefix("scheme:"), !trimmed.dropFirst("scheme:".count).trimmingCharacters(in: .whitespaces).isEmpty {
                return true
            }
        }
        return false
    }

    /// The simulator IDs a config's profiles name, each once.
    public static func simulatorIDs(in yaml: String) -> [String] {
        values(of: ["simulatorId:"], in: yaml)
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

    /// The workspace and project paths a config's profiles point at, each once.
    public static func containerPaths(in yaml: String) -> [String] {
        values(of: ["workspacePath:", "projectPath:"], in: yaml)
    }

    /// A YAML single-quoted scalar, so names with `: `, ` #` or quotes stay intact.
    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    static func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("'"), value.hasSuffix("'") else { return value }
        return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
    }
}
