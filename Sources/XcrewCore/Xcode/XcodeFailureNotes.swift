import Foundation

/// What a failed MobileBuildMCP build or test whose errors another SDK or toolchain gives may come from, beyond the pin:
/// CI on another Xcode, a pin to suggest, and an open Xcode other than the one building. Said on the failure it can
/// explain, each only when it holds; the doctor, which checks what xcrew needs to run, says none of them.
enum XcodeFailureNotes {
    static func notes(_ xcodes: XcodeSnapshot) -> [String] {
        var notes: [String] = []
        let builds = xcodes.forBuilds
        let buildsCovered = { (versions: [CIXcodes.Named]) in versions.contains { named in builds.map { CIXcodes.covers(named.version, $0.version) } == true } }
        // Without a pin, with several Xcodes to choose from, the pin that would match CI says it all.
        if xcodes.pin == nil, xcodes.installed.count > 1, let ci = xcodes.ci.first, !buildsCovered(xcodes.ci) {
            notes.append("xcrew: several Xcodes are installed and CI uses Xcode \(ci.version) (\(ci.file):\(ci.line)), but nothing pins one, so builds use \(builds?.label ?? "the selected Xcode"), and a different SDK from CI's may be the cause; `echo \(ci.version) > \(Project.xcodePinFile)` pins CI's")
        } else if let other = xcodes.ci.first, let ours = xcodes.pin?.version ?? builds?.version, !xcodes.ci.contains(where: { CIXcodes.covers($0.version, ours) }) {
            let here = xcodes.pin == nil ? "builds here use Xcode \(ours)" : "this project pins Xcode \(ours)"
            notes.append("xcrew: CI uses Xcode \(other.version) (\(other.file):\(other.line)), but \(here), so a different SDK from CI's may be the cause; moving CI to \(ours), or pinning \(other.version) in \(Project.xcodePinFile), puts CI and these builds on one Xcode")
        }
        if let builds, let other = xcodes.open.first(where: { !$0.isSameToolchain(as: builds) }) {
            notes.append("xcrew: the Xcode MCP works through the open \(other.label), but MobileBuildMCP builds with \(builds.label), so their builds and errors can disagree; once \(other.label) is quit, opening \(builds.path) puts the Xcode MCP and MobileBuildMCP on \(builds.label)")
        }
        return notes
    }
}
