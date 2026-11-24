/// The scheme that launches the project's app, for what Claude reads beside the Xcode MCP's runs, which run Xcode's
/// active scheme and take none of their own (docs/findings.md, *Xcode's scheme for the Xcode MCP's runs*).
public struct AppScheme: Sendable {
    /// The config's `app` profile's scheme.
    public let name: String
    /// Whether a generator writes the project, whose regenerate resets Xcode's selection.
    public let isGenerated: Bool

    public init(name: String, isGenerated: Bool) {
        (self.name, self.isGenerated) = (name, isGenerated)
    }

    /// The config's `app` profile's scheme; nil without one, as the project's own schemes aren't read for it.
    public static func of(_ project: Project) -> AppScheme? {
        project.scheme(ofProfile: "app").map { AppScheme(name: $0, isGenerated: project.isGenerated) }
    }

    /// What the session starts with: what `RunProject` runs, how to change it, and the app's scheme.
    public var briefingNote: String {
        "The Xcode MCP's `RunProject` builds and runs Xcode's active scheme and takes no scheme of its own; `XcodeSwitchScheme` selects one and keeps the run destination. `\(name)` launches the app." + reset
    }

    /// What a run that built and launched nothing adds: why that can be, and the app's scheme.
    public var failedLaunchNote: String {
        "xcrew: `RunProject` built Xcode's active scheme and launched nothing from it, which happens when that scheme has no app to launch, and also when the app fails at launch. `\(name)` launches the app. `XcodeSwitchScheme` selects a scheme and keeps the run destination." + reset
    }

    private var reset: String {
        isGenerated ? " A regenerate resets Xcode's selection to the first scheme in alphabetical order." : ""
    }
}
