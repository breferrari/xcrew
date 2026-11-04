import Foundation
import XcrewCore

/// A report made as a test gives it: a home's path and a runner, and a Machine only where the test has one. Without one,
/// the Machine is that home's, with no environment, its apps under that home and a fixed clock, so no test reads the
/// Mac's own Xcode or the wall clock.
extension Report {
    /// When a report made without a Machine says it's now.
    static let testNow = Date(timeIntervalSince1970: 1_793_750_400)

    /// The Machine a report is made on: `given`, with the test's home and runner in place of its own, or that home's.
    static func machine(home: String, runner: any CommandRunning, given: Machine?) -> Machine {
        let home = URL(fileURLWithPath: home)
        guard let given else { return Machine(environment: [:], home: home, runner: runner, applications: home.appending(path: "Applications"), now: { testNow }) }
        return Machine(environment: given.environment, home: home, runner: runner, processID: given.processID, applications: given.applications, now: given.now)
    }

    /// A finished run told from its log, as `make(kind:log:machine:)`, xcresulttool answering from `runner`.
    public static func make(kind: Kind, log: String, runner: any CommandRunning, repeated: Bool = false, listsPassed: Bool = false) async -> Report {
        await make(kind: kind, log: log, machine: machine(home: "/nonexistent", runner: runner, given: nil), repeated: repeated, listsPassed: listsPassed)
    }

    /// A call moved to the background, as `make(kind:notification:log:launches:server:repeated:listsPassed:project:machine:)`.
    public static func make(kind: Kind, notification text: String, log: String?, launches: Bool = false, server: Server, home: String, runner: any CommandRunning, repeated: Bool = false, listsPassed: Bool = false, project: Project? = nil, machine: Machine? = nil) async -> Report {
        await make(kind: kind, notification: text, log: log, launches: launches, server: server, repeated: repeated, listsPassed: listsPassed, project: project, machine: Self.machine(home: home, runner: runner, given: machine))
    }

    /// A call's result, as `make(kind:output:repeated:listsPassed:project:machine:)`.
    public static func make(kind: Kind, output: ToolOutput, home: String, runner: any CommandRunning, repeated: Bool = false, listsPassed: Bool = false, project: Project? = nil, machine: Machine? = nil) async -> Report {
        await make(kind: kind, output: output, repeated: repeated, listsPassed: listsPassed, project: project, machine: Self.machine(home: home, runner: runner, given: machine))
    }
}
