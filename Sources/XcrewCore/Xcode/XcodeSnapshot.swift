import Foundation

/// One look at the Mac's Xcodes for a project, taken once per doctor run and shared by its checks and `xcrew xcode`.
public struct XcodeSnapshot: Sendable {
    /// What the project's pin comes to, with the install it names and its file.
    public enum PinState: Sendable, Equatable {
        case none
        case notInstalled(pin: String, file: String)
        /// No MobileBuildMCP serves the project yet; it starts with the pin.
        case waiting(XcodeInstall, file: String)
        case applied(XcodeInstall, file: String)
        case notApplied(XcodeInstall, file: String, why: String)
    }

    public let installed: [XcodeInstall]
    public let selected: XcodeInstall?
    public let open: [XcodeInstall]
    public let pin: (version: String, file: String)?
    /// The launcher's record of how the server running started; nil when no record is as new as it.
    public let launch: Xcodes.Launch?
    /// Whether a MobileBuildMCP serves the project now.
    public let isServing: Bool
    public let ci: [CIXcodes.Named]

    /// How much older than the server's start its record may be: `ps` gives the server's age in whole seconds.
    static let ageSlack: TimeInterval = 1

    public static func take(of project: Project, on machine: Machine) async -> XcodeSnapshot {
        await take(of: project, on: machine, processes: Once { await ProcessList.load(using: machine.runner) })
    }

    /// The snapshot from a process list another reader shares, listed alongside the Xcodes.
    static func take(of project: Project, on machine: Machine, processes: Once<ProcessList>) async -> XcodeSnapshot {
        async let installed = Xcodes.installed(on: machine)
        async let selected = Xcodes.selected(on: machine)
        let list = await processes.value()
        let server = await list.mobileBuildMCPServer(serving: project, forSessionOf: machine.processID, using: machine.runner)?.server
        // The launcher writes its record and then becomes the server, so the server's record is no older than its start.
        let started = server.map { Date(timeIntervalSinceNow: -TimeInterval($0.elapsed) - ageSlack) }
        let launch = Xcodes.lastLaunch(of: project, on: machine).flatMap { record in started.flatMap { record.written >= $0 ? record.launch : nil } }
        return XcodeSnapshot(installed: await installed, selected: await selected, open: Xcodes.running(in: list), pin: project.xcodePin, launch: launch, isServing: server != nil, ci: CIXcodes.named(in: project))
    }

    /// The Xcode MobileBuildMCP builds with: the pinned one when its server started with it or hasn't started yet, else
    /// the selected one.
    public var forBuilds: XcodeInstall? {
        switch pinState {
        case let .applied(install, _), let .waiting(install, _): install
        case .none, .notInstalled, .notApplied: selected
        }
    }

    public var pinState: PinState {
        guard let pin else { return .none }
        guard let match = Xcodes.matching(pin.version, in: installed) else { return .notInstalled(pin: pin.version, file: pin.file) }
        guard isServing else { return .waiting(match, file: pin.file) }
        switch launch {
        case let .applied(developer) where Xcodes.app(holding: developer).map(ProjectLayout.canonical) == ProjectLayout.canonicalPath(match.path):
            return .applied(match, file: pin.file)
        case .applied: return .notApplied(match, file: pin.file, why: "it started with another Xcode")
        case let .some(other): return .notApplied(match, file: pin.file, why: other.reason ?? "")
        case nil: return .notApplied(match, file: pin.file, why: "it started before the pin applied")
        }
    }
}
