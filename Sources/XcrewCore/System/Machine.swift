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
    /// When the call this machine runs must have answered by; nil outside a call, as in a test that sets none.
    public let deadline: Date?

    public init(environment: [String: String], home: URL, runner: any CommandRunning, processID: Int32 = ProcessInfo.processInfo.processIdentifier, applications: URL = URL(fileURLWithPath: "/Applications"), now: @escaping @Sendable () -> Date = { Date() }, deadline: Date? = nil) {
        self.environment = environment
        self.home = home
        self.runner = runner
        self.processID = processID
        self.applications = applications
        self.now = now
        self.deadline = deadline
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

    /// This machine with `name` set to `value` in its environment.
    public func setting(_ name: String, to value: String) -> Machine {
        Machine(environment: environment.merging([name: value]) { $1 }, home: home, runner: runner, processID: processID, applications: applications, now: now, deadline: deadline)
    }

    /// This machine with its commands run by `runner`.
    public func running(_ runner: any CommandRunning) -> Machine {
        Machine(environment: environment, home: home, runner: runner, processID: processID, applications: applications, now: now, deadline: deadline)
    }

    /// This machine for a call that must have answered by `deadline`, each command it starts given what's left of it.
    public func answering(by deadline: Date) -> Machine {
        Machine(environment: environment, home: home, runner: DeadlineRunner(runner, deadline: deadline, now: now), processID: processID, applications: applications, now: now, deadline: deadline)
    }

    /// The time left before the deadline, none once it's past; `otherwise` with no deadline.
    public func timeLeft(otherwise: Duration) -> Duration {
        deadline.map { .seconds(max(0, $0.timeIntervalSince(now()))) } ?? otherwise
    }

    /// A variable's value, treating an empty one as unset.
    public func value(_ name: String) -> String? {
        guard let value = environment[name], !value.isEmpty else { return nil }
        return value
    }
}
