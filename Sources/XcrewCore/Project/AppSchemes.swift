import Foundation

/// The schemes that launch the project's app, for what Claude reads beside the Xcode MCP's runs, which run Xcode's
/// active scheme and take none of their own (docs/findings.md, *Xcode's scheme for the Xcode MCP's runs*).
public struct AppSchemes: Sendable, Equatable {
    /// The config's `app` profile's scheme, else the shared schemes that build an app, narrowed as setup picks one.
    public let names: [String]
    /// Whether a generator writes the project, whose regenerate resets Xcode's selection.
    public let isGenerated: Bool

    public init(names: [String], isGenerated: Bool) {
        (self.names, self.isGenerated) = (names, isGenerated)
    }

    public static func of(_ project: Project, home: URL) -> AppSchemes {
        let layout = project.layout(.repository)
        let yaml = try? String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8)
        if let scheme = yaml.flatMap({ ConfigRenderer.schemeToBuild(in: $0, profile: "app") }) {
            return AppSchemes(names: [scheme], isGenerated: layout.generator != nil)
        }
        let configured = yaml.flatMap { SetupChoices.Picks.container(in: $0, root: project.root, home: home) }
        let containers = configured.map { [URL(fileURLWithPath: ConfigRenderer.resolved($0, root: project.root, home: home))] }
            ?? layout.containers.map { project.root.appending(path: $0) }
        let root = ProjectLayout.canonical(project.root)
        var seen = Set<String>()
        let apps = containers.flatMap { SetupChoices.schemes(of: $0, from: root) }.filter { $0.roles.contains(.app) && seen.insert($0.name).inserted }
        let named = apps.filter { $0.name == $0.app }
        let picked = apps.count == 1 ? apps : named.count == 1 ? named : apps
        return AppSchemes(names: picked.map(\.name).sorted(), isGenerated: layout.generator != nil)
    }

    /// What the session starts with: what `RunProject` runs, how to change it, and the app's scheme.
    public var briefingNote: String? {
        named.map { "The Xcode MCP's `RunProject` builds and runs Xcode's active scheme and takes no scheme of its own; `XcodeSwitchScheme` selects one and keeps the run destination. " + $0 + reset }
    }

    /// What a run that built and launched nothing adds: why that can be, and the app's scheme.
    public var failedLaunchNote: String? {
        named.map { "xcrew: `RunProject` built Xcode's active scheme and launched nothing from it, which happens when that scheme has no app to launch, and also when the app fails at launch. " + $0 + " `XcodeSwitchScheme` selects a scheme and keeps the run destination." + reset }
    }

    private static let shown = 3

    private var named: String? {
        guard let only = names.first else { return nil }
        if names.count == 1 { return "`\(only)` launches the app." }
        let quoted = names.prefix(Self.shown).map { "`\($0)`" }
        let more = names.count - quoted.count
        let listed = more > 0 ? quoted.joined(separator: ", ") + " and \(more) more" : quoted.dropLast().joined(separator: ", ") + " and " + quoted[quoted.count - 1]
        return "Schemes that launch an app: \(listed)."
    }

    private var reset: String {
        isGenerated ? " A regenerate resets Xcode's selection to the first scheme in alphabetical order." : ""
    }
}
