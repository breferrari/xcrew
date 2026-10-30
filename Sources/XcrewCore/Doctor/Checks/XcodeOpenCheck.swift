import Foundation

/// The Xcode MCP works through the Xcode that's open, which no pin changes; MobileBuildMCP builds with the pinned or
/// selected one. Two different ones are two toolchains in one session.
struct XcodeOpenCheck: Check {
    let id = "xcode/open"
    let title = "The open Xcode is the one builds use"

    func run(_ context: CheckContext) async -> CheckResult {
        let open = await Xcodes.running(on: context.machine)
        guard let first = open.first else { return .pass("Xcode isn't open") }
        guard let builds = await Xcodes.forBuilds(of: context.project, on: context.machine) else { return .skip("no Xcode is selected here") }
        guard let other = open.first(where: { !Xcodes.same($0, builds) }) else {
            return .pass("the open Xcode \(first.version) is the one MobileBuildMCP builds with")
        }
        return .warn("two toolchains in one session: the Xcode MCP works through the open Xcode \(other.version), but MobileBuildMCP builds with Xcode \(builds.version), so their builds, errors and tests can disagree: quit Xcode \(other.version) and open \(builds.path)")
    }
}
