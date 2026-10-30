import Foundation

/// A build that found its build database locked by another build of the same DerivedData: most often an xcodebuild a
/// stopped call left running, since stopping a MobileBuildMCP call doesn't stop the xcodebuild it started (docs/findings.md,
/// *Builds that fail because of the Mac*). Xcode's own wording, `unable to attach DB` … `database is locked`, names the
/// database, whose DerivedData the orphan's command line names too.
struct LockedBuildDatabase: MachineCause {
    func explanation(of failure: FailureEvidence) async -> String? {
        guard let error = failure.errors.first(where: { $0.message.contains("database is locked") && !$0.isInside(root: failure.root) }) else { return nil }
        let derivedData = error.message.firstMatch(of: /build database "(.+?)\/Build\/Intermediates\.noindex\/XCBuildData\/build\.db"/).map { String($0.1) }
        let builds = await ProcessList.load(using: failure.runner).processes.filter { process in
            process.program == "xcodebuild" && derivedData.map { process.command.contains("-derivedDataPath \($0)") } == true
        }
        guard let orphan = builds.first else {
            return "another build held its build database (\"database is locked\") and has since ended. Build again."
        }
        let destination = orphan.command.firstMatch(of: /-destination ['"]?(.+?)['"]?(?= -|$)/).map { ", for \($0.1)" } ?? ""
        return "an xcodebuild left running holds its build database (\"database is locked\"): pid \(orphan.id)\(destination), running \(orphan.elapsed / 60) min. A build stopped before it finished leaves one. Stop it, then build again: kill \(orphan.id)"
    }
}
