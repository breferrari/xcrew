import Foundation

/// What xcrew may read from the machine: environment variables, the home folder, and the
/// programs it runs. Passed in rather than read globally, so every behaviour is testable.
public struct Machine: Sendable {
    public let environment: [String: String]
    public let home: URL
    public let runner: any CommandRunning
    /// This process's id.
    public let processID: Int32

    public init(environment: [String: String], home: URL, runner: any CommandRunning, processID: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.environment = environment
        self.home = home
        self.runner = runner
        self.processID = processID
    }

    public static let live = Machine(
        environment: ProcessInfo.processInfo.environment,
        home: FileManager.default.homeDirectoryForCurrentUser,
        runner: SystemCommandRunner()
    )

    /// Whether MobileBuildMCP is on the PATH; the doctor and the session briefing both ask.
    public var hasMobileBuildMCP: Bool { runner.which("mobilebuildmcp") != nil }

    /// Where xcrew keeps what it can work out again: the folder `bin/xcrew` builds into.
    public var cacheFolder: URL {
        value("XCREW_CACHE").map { URL(fileURLWithPath: $0) } ?? home.appending(path: "Library/Caches/xcrew")
    }

    /// A variable's value, treating an empty one as unset.
    public func value(_ name: String) -> String? {
        guard let value = environment[name], !value.isEmpty else { return nil }
        return value
    }
}
