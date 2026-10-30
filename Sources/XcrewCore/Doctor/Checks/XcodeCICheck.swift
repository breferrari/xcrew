import Foundation

/// CI builds with the Xcode the project does, its pin, else the one builds use here: one of the versions CI names covers
/// it, as setup-xcode reads `26` as the newest 26.x, so a matrix over several Xcodes passes when the project's is in it.
struct XcodeCICheck: Check {
    let id = "xcode/ci"
    let title = "CI uses the project's Xcode"

    func run(_ context: CheckContext) async -> CheckResult {
        let xcodes = await context.xcodes.value()
        guard let other = xcodes.ci.first else { return .pass("CI names no Xcode version") }
        let pinned = xcodes.pin?.version
        guard let ours = pinned ?? xcodes.forBuilds?.version else { return .skip("no Xcode is selected here") }
        guard !xcodes.ci.contains(where: { CIXcodes.covers($0.version, ours) }) else { return .pass("CI uses Xcode \(ours) too") }
        let here = pinned == nil ? "builds here use Xcode \(ours)" : "this project pins Xcode \(ours)"
        return .warn("CI uses Xcode \(other.version) (\(other.file):\(other.line)), but \(here), so results can differ from CI's: move CI to \(ours), or pin \(other.version) in \(Project.xcodePinFile)")
    }
}
