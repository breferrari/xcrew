import Foundation

/// A build that found its build database locked by another build of the same DerivedData: most often an xcodebuild a
/// stopped call left running, since stopping a MobileBuildMCP call doesn't stop the xcodebuild it started (docs/findings.md,
/// *Builds that fail because of the Mac*). Xcode's own wording, `unable to attach DB` … `database is locked`, names the
/// database; the process holding it is the one `lsof` says has it open, or else an xcodebuild building into its DerivedData.
struct LockedBuildDatabase: MachineCause {
    func explanation(of failure: FailureEvidence) async -> String? {
        guard let error = failure.errors(containing: "database is locked").first else { return nil }
        guard let database = error.message.firstMatch(of: #/build database "(.+?/Build/Intermediates\.noindex/XCBuildData/build\.db)"/#).map({ String($0.1) }) else {
            return Self.free
        }
        let derivedData = String(database.dropLast("/Build/Intermediates.noindex/XCBuildData/build.db".count))
        async let opened = failure.runner.run("lsof", "-t", database)
        let processes = await ProcessList.load(using: failure.runner).processes
        let holders = await opened.stdout.split(whereSeparator: \.isNewline).compactMap { Int32($0) }
        let holder = processes.first { holders.contains($0.id) }
            ?? processes.first { $0.program == "xcodebuild" && ($0.command.hasSuffix("-derivedDataPath \(derivedData)") || $0.command.contains("-derivedDataPath \(derivedData) ")) }
        guard let holder else { return Self.free }
        return Self.held(by: holder)
    }

    /// When nothing holds the database any more.
    static let free = "its build database is locked (\"database is locked\") by another build, and no process holds it now. Build again."

    /// The process holding the database, its destination when it's an xcodebuild, how long it has run, and how to stop it.
    static func held(by holder: ProcessList.Process) -> String {
        let name = holder.program == "xcodebuild" ? "an xcodebuild left running" : (holder.program.isEmpty ? "process \(holder.id)" : holder.program)
        let destination = holder.command.firstMatch(of: #/-destination ['"]?(.+?)['"]?(?= -|$)/#).map { ", for \($0.1)" } ?? ""
        let running = holder.elapsed < 60 ? "\(holder.elapsed) s" : "\(holder.elapsed / 60) min"
        return "\(name) holds its build database (\"database is locked\"): pid \(holder.id)\(destination), running \(running). A build stopped partway leaves one. Stop it, then build again: kill \(holder.id)"
    }
}
