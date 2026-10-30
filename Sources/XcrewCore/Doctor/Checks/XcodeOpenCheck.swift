import Foundation

/// The Xcode MCP works through the Xcode that's open, which no pin changes; MobileBuildMCP builds with the pinned or
/// selected one. Two different ones are two toolchains in one session. The headless Xcode MCP runs with no Xcode app
/// open, which the process list doesn't show.
struct XcodeOpenCheck: Check {
    let id = "xcode/open"
    let title = "The open Xcode is the one builds use"

    func run(_ context: CheckContext) async -> CheckResult {
        let xcodes = await context.xcodes.value()
        guard !xcodes.open.isEmpty else {
            let headless = await context.xcodeMCPStatus.value()
            return .pass(headless.succeeded && headless.stdout.contains("Permission: enabled") ? "no Xcode window is open; the Xcode MCP runs headless" : "Xcode isn't open")
        }
        guard let builds = xcodes.forBuilds else { return .skip("no Xcode is selected here") }
        guard let other = xcodes.open.first(where: { !$0.isSameToolchain(as: builds) }) else {
            return .pass("the open \(builds.label) is the one MobileBuildMCP builds with")
        }
        return .warn("two toolchains in one session: the Xcode MCP works through the open \(other.label), but MobileBuildMCP builds with \(builds.label), so their builds, errors and tests can disagree: quit \(other.label) and open \(builds.path)")
    }
}
