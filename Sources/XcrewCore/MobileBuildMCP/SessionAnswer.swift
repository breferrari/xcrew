import Foundation

/// What a MobileBuildMCP session tool's text answer says (docs/findings.md, *MobileBuildMCP's session answers*): the
/// profiles `session_show_defaults` lists, each with its scheme and simulator, or the profile a switch activated,
/// `✅ Activated profile (unit profile)`. The listing names no profile in use. A text in neither shape says nothing.
public struct SessionAnswer: Codable, Equatable, Sendable {
    public struct Profile: Codable, Equatable, Sendable {
        public var scheme: String?
        public var simulatorName: String?

        public init(scheme: String? = nil, simulatorName: String? = nil) {
            self.scheme = scheme
            self.simulatorName = simulatorName
        }
    }

    public var profiles: [String: Profile]?
    public var currentProfile: String?

    public init(profiles: [String: Profile]? = nil, currentProfile: String? = nil) {
        self.profiles = profiles
        self.currentProfile = currentProfile
    }

    /// MobileBuildMCP's name for the unnamed profile, which a switch's text writes `(default profile)`.
    static let unnamed = "(default)"

    public static func read(_ text: String) -> SessionAnswer {
        if let profiles = listing(text) { return SessionAnswer(profiles: profiles) }
        return SessionAnswer(currentProfile: activated(text))
    }

    /// Each `📁 <profile>` section's `├ key: value` lines, every section with a scheme and a simulator line, under the
    /// listing's header; `(not set)` is none.
    static func listing(_ text: String) -> [String: Profile]? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "⚙️ Show Defaults" }) else { return nil }
        var sections: [(name: String, keys: [String: String])] = []
        for line in lines {
            if let heading = line.firstMatch(of: /^📁 (.+)$/) {
                sections.append((String(heading.1), [:]))
            } else if let entry = line.firstMatch(of: /^ {2}[├└] (\w+): (.*)$/), !sections.isEmpty {
                sections[sections.count - 1].keys[String(entry.1)] = String(entry.2)
            }
        }
        guard !sections.isEmpty, sections.allSatisfy({ $0.keys["scheme"] != nil && $0.keys["simulatorName"] != nil }) else { return nil }
        let value = { (written: String?) in written == "(not set)" ? nil : written }
        return Dictionary(sections.map { ($0.name, Profile(scheme: value($0.keys["scheme"]), simulatorName: value($0.keys["simulatorName"]))) }) { _, last in last }
    }

    static func activated(_ text: String) -> String? {
        guard let named = text.firstMatch(of: /(?m)^✅ Activated profile \((.+) profile\)$/)?.1 else { return nil }
        return named == "default" ? unnamed : String(named)
    }
}
