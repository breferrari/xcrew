import Foundation

/// The project's `.xcode-version` names an installed Xcode, and MobileBuildMCP's server started with it. Without a pin,
/// one is suggested only when several Xcodes are installed and CI names its own: a pin is the team's choice.
struct XcodePinCheck: Check {
    let id = "xcode/pin"
    let title = "The project's Xcode pin applies"

    func run(_ context: CheckContext) async -> CheckResult {
        let installed = await Xcodes.installed(on: context.machine)
        let builds = await Xcodes.forBuilds(of: context.project, on: context.machine)
        let using = builds.map { "Xcode \($0.version)" } ?? "the selected Xcode"
        guard let pin = Xcodes.pin(of: context.project) else {
            guard installed.count > 1, let ci = Xcodes.ci(of: context.project).first(where: { $0.version != nil }), let version = ci.version else {
                return .pass("no pin, and nothing to choose between")
            }
            return .warn("several Xcodes are installed and CI uses Xcode \(version) (\(ci.file):\(ci.line)), but nothing pins one, so builds use \(using): pin CI's with echo \(version) > \(Xcodes.pinFile)")
        }
        guard let match = Xcodes.matching(pin.version, in: installed) else {
            return .fail("the project pins Xcode \(pin.version) (\(pin.file)), but no installed Xcode is \(pin.version), so MobileBuildMCP builds with \(using): xcodes install \(pin.version)")
        }
        let why: String
        switch Xcodes.launch(of: context.project, on: context.machine) {
        case let .applied(developer):
            if let applied = Xcodes.app(holding: developer), ProjectLayout.canonical(applied) == ProjectLayout.canonicalPath(match.path) {
                return .pass("Xcode \(match.version), at \(match.path)")
            }
            why = "it started with another Xcode"
        case let .notApplied(reason): why = reason
        case nil: why = "no record of its start, so it started before the pin applied"
        }
        return .warn("the project pins Xcode \(pin.version) (\(pin.file)), but MobileBuildMCP started without it (\(why)), so it builds with \(using): restart Claude Code")
    }
}
