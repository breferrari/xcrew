import Foundation

/// A compiler warning MobileBuildMCP lists once for each place it fires, as one warning with how many
/// times and where: a deprecation used across a module otherwise fills the result with one message.
enum RepeatedWarnings {
    /// A file and, when the server gave one, the line in it.
    struct Location: Sendable, Equatable {
        let path: String
        let line: String?

        init(path: String, line: String?) {
            self.path = path
            self.line = line
        }

        /// `/path/File.swift:12`, as MobileBuildMCP's JSON writes a warning's place.
        init(_ text: String) {
            let place = MobileBuildMCPLine.place(text)
            self.init(path: place?.path ?? text, line: place?.line)
        }
    }

    struct Warning: Sendable {
        let message: String
        let location: Location?
    }

    struct Group: Sendable {
        let message: String
        var count: Int
        var locations: [Location]
    }

    /// Each distinct message once, in the order first listed; nil when no message repeats.
    static func grouped(_ warnings: [Warning]) -> [Group]? {
        var groups: [Group] = []
        var index: [String: Int] = [:]
        for warning in warnings {
            let at = index[warning.message, default: groups.count]
            if at == groups.count {
                index[warning.message] = at
                groups.append(Group(message: warning.message, count: 0, locations: []))
            }
            groups[at].count += 1
            // A place listed twice, say once per architecture, is still one place.
            if let location = warning.location, !groups[at].locations.contains(location) { groups[at].locations.append(location) }
        }
        return groups.count < warnings.count ? groups : nil
    }

    /// `/a/A.swift:4, :5, /b/B.swift:9`: a file's path, then each further line in it until another file's.
    static func locations(_ locations: [Location]) -> String {
        zip([nil] + locations.map(\.path), locations).map { previous, location in
            guard let line = location.line else { return location.path }
            return previous == location.path ? ":\(line)" : "\(location.path):\(line)"
        }.joined(separator: ", ")
    }

    /// `message (3×, /a/A.swift:4, :5, :6)`, a warning as listed once for all its places.
    static func line(_ group: Group) -> String {
        let places = group.locations.isEmpty ? "" : ", " + locations(group.locations)
        return "\(group.message) (\(group.count)×\(places))"
    }
}
