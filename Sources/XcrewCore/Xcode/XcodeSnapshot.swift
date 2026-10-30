import Foundation

/// One look at the Mac's Xcodes for a project, taken once per doctor run and shared by its checks and `xcrew xcode`.
public struct XcodeSnapshot: Sendable {
    /// What the project's pin comes to: none, none installed, or an install the server started with, or without and why.
    public enum PinState: Sendable, Equatable {
        case none
        case notInstalled(pin: String, file: String)
        case applied(XcodeInstall)
        case notApplied(pin: String, file: String, why: String)
    }

    public let installed: [XcodeInstall]
    public let selected: XcodeInstall?
    public let open: [XcodeInstall]
    public let pin: (version: String, file: String)?
    public let launch: Xcodes.Launch?
    public let ci: [CIXcodes.Named]

    public static func take(of project: Project, on machine: Machine) async -> XcodeSnapshot {
        async let installed = Xcodes.installed(on: machine)
        async let selected = Xcodes.selected(on: machine)
        async let open = Xcodes.running(on: machine)
        return XcodeSnapshot(installed: await installed, selected: await selected, open: await open, pin: project.xcodePin, launch: Xcodes.launch(of: project, on: machine), ci: CIXcodes.named(in: project))
    }

    /// The Xcode MobileBuildMCP builds with: the one its server started with, else the selected one.
    public var forBuilds: XcodeInstall? {
        if case let .applied(developer) = launch, let install = Xcodes.app(holding: developer).flatMap(Xcodes.install) { return install }
        return selected
    }

    public var pinState: PinState {
        guard let pin else { return .none }
        guard let match = Xcodes.matching(pin.version, in: installed) else { return .notInstalled(pin: pin.version, file: pin.file) }
        let why = switch launch {
        case let .applied(developer):
            Xcodes.app(holding: developer).map(ProjectLayout.canonical) == ProjectLayout.canonicalPath(match.path) ? nil : "it started with another Xcode"
        case let .some(other): other.reason
        case nil: "no record of its start, so it started before the pin applied"
        }
        return why.map { .notApplied(pin: pin.version, file: pin.file, why: $0) } ?? .applied(match)
    }
}
