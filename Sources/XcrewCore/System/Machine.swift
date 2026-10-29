import Foundation

/// What xcrew may read from the machine: environment variables, the home folder, and the
/// programs it runs. Passed in rather than read globally, so every behaviour is testable.
public struct Machine: Sendable {
    public let environment: [String: String]
    public let home: URL
    public let runner: any CommandRunning

    public init(environment: [String: String], home: URL, runner: any CommandRunning) {
        self.environment = environment
        self.home = home
        self.runner = runner
    }

    public static let live = Machine(
        environment: ProcessInfo.processInfo.environment,
        home: FileManager.default.homeDirectoryForCurrentUser,
        runner: SystemCommandRunner()
    )

    /// Whether MobileBuildMCP is on the PATH; the doctor and the session briefing both ask.
    public var hasMobileBuildMCP: Bool { runner.which("mobilebuildmcp") != nil }

    /// A variable's value, treating an empty one as unset.
    public func value(_ name: String) -> String? {
        guard let value = environment[name], !value.isEmpty else { return nil }
        return value
    }
}
