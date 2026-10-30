import Foundation

/// The project's `.xcode-version` names an installed Xcode, and MobileBuildMCP's server started with it. Without a pin,
/// one is suggested only when several Xcodes are installed and CI names its own: a pin is the team's choice.
struct XcodePinCheck: Check {
    let id = "xcode/pin"
    let title = "The project's Xcode pin applies"

    func run(_ context: CheckContext) async -> CheckResult {
        let xcodes = await context.xcodes.value()
        let using = xcodes.forBuilds?.label ?? "the selected Xcode"
        let pinned = xcodes.pin?.version ?? ""
        switch xcodes.pinState {
        case .none:
            let builds = xcodes.forBuilds?.version
            guard xcodes.installed.count > 1, let ci = xcodes.ci.first, !xcodes.ci.contains(where: { named in builds.map { CIXcodes.covers(named.version, $0) } == true }) else {
                return .pass("no pin, and nothing to choose between")
            }
            return .warn("several Xcodes are installed and CI uses Xcode \(ci.version) (\(ci.file):\(ci.line)), but nothing pins one, so builds use \(using): pin CI's with echo \(ci.version) > \(Project.xcodePinFile)")
        case let .notInstalled(pin, file):
            let install = context.runner.which("xcodes") == nil ? "install Xcode \(pin) from https://developer.apple.com/download/all/" : "xcodes install \(pin)"
            // Every mismatch is a warning: the Mac still builds, with another Xcode than the project expects.
            guard let builds = xcodes.forBuilds else {
                return .warn("the project pins Xcode \(pin) (\(file)), but no installed Xcode is \(pin), so MobileBuildMCP builds with \(using): \(install)")
            }
            let lead = "builds use \(builds.label) while the project pins Xcode \(pin) (\(file))"
            if Version.major(of: pin) == nil || Version.major(of: pin) != Version.major(of: builds.version) {
                return .warn("\(lead), and a build may fail with another major version's SDK: \(install)")
            }
            if Version(pin) > Version(builds.version) {
                return .warn("\(lead), and a build may fail where the code uses the newer SDK: \(install)")
            }
            return .warn("\(lead); a minor or patch difference rarely matters except to match CI's diagnostics: optionally, \(install)")
        case let .waiting(install, _):
            return .skip("MobileBuildMCP isn't running for this project; it starts with \(install.label)")
        case let .applied(install, _):
            return .pass("\(install.label), at \(install.path)")
        case let .notApplied(_, file, why):
            return .warn("the project pins Xcode \(pinned) (\(file)), but MobileBuildMCP started without it (\(why)), so it builds with \(using): restart Claude Code")
        }
    }
}
