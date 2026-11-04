import Foundation

/// What xcrew may read from the machine: environment variables, the home folder, the
/// programs it runs, and the time. Passed in rather than read globally, so every behaviour is testable.
public struct Machine: Sendable {
    public let environment: [String: String]
    public let home: URL
    public let runner: any CommandRunning
    /// This process's id.
    public let processID: Int32
    /// Where apps are installed, Xcode among them.
    public let applications: URL
    /// The time now: the wall clock, or a test's own.
    public let now: @Sendable () -> Date
    /// How its own files are read: the disk, or a test's folders.
    public let files: any FileReading

    public init(environment: [String: String], home: URL, runner: any CommandRunning, processID: Int32 = ProcessInfo.processInfo.processIdentifier, applications: URL = URL(fileURLWithPath: "/Applications"), now: @escaping @Sendable () -> Date = { Date() }, files: any FileReading) {
        self.environment = environment
        self.home = home
        self.runner = runner
        self.processID = processID
        self.applications = applications
        self.now = now
        self.files = files
    }

    /// An app a text or a command names, as this machine has it: one in `/Applications` is in its applications folder,
    /// which is that folder on a Mac and a test's own on a test's Machine, at its real path, as listing it gives its apps.
    public func onThisMachine(_ url: URL) -> URL {
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count > 2, parts[0] == "/", parts[1] == "Applications" else { return url }
        return parts.dropFirst(2).reduce(URL(fileURLWithPath: ProjectLayout.canonical(applications))) { $0.appending(path: $1) }
    }

    public static let live = Machine(
        environment: ProcessInfo.processInfo.environment,
        home: FileManager.default.homeDirectoryForCurrentUser,
        runner: SystemCommandRunner(),
        files: LocalFiles()
    )

    /// Whether MobileBuildMCP is on the PATH; the doctor and the session briefing both ask.
    public var hasMobileBuildMCP: Bool { runner.which("mobilebuildmcp") != nil }

    /// Where xcrew keeps what it can work out again: the folder `bin/xcrew` builds into.
    public var cacheFolder: URL {
        value("XCREW_CACHE").map { URL(fileURLWithPath: $0) } ?? home.appending(path: "Library/Caches/xcrew")
    }

    /// This machine with `name` set to `value` in its environment.
    public func setting(_ name: String, to value: String) -> Machine {
        Machine(environment: environment.merging([name: value]) { $1 }, home: home, runner: runner, processID: processID, applications: applications, now: now, files: files)
    }

    /// This machine with its commands run by `runner`.
    public func running(_ runner: any CommandRunning) -> Machine {
        Machine(environment: environment, home: home, runner: runner, processID: processID, applications: applications, now: now, files: files)
    }

    /// A variable's value, treating an empty one as unset.
    public func value(_ name: String) -> String? {
        guard let value = environment[name], !value.isEmpty else { return nil }
        return value
    }
}
