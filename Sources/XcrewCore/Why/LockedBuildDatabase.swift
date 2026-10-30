import Foundation

/// A build that found its build database locked by another build: most often an xcodebuild a stopped call left running,
/// since stopping a MobileBuildMCP call doesn't stop the xcodebuild it started (docs/findings.md, *Builds that fail because
/// of the Mac*). Only Xcode's own wording counts, `accessing build database "<path>/build.db": database is locked`: a
/// test's SQLite error says the same last words and is the code's. The process holding it is an xcodebuild `lsof` says
/// has it open, or one building into its DerivedData, else whatever else holds it, which isn't one to stop.
struct LockedBuildDatabase: MachineCause {
    func explanation(of failure: FailureEvidence) async -> String? {
        guard let database = failure.errors(containing: "database is locked").lazy
            .compactMap({ $0.message.firstMatch(of: #/accessing build database "([^"]+/build\.db)": database is locked/#).map { String($0.1) } }).first
        else { return nil }
        async let opened = failure.runner.run("lsof", "-t", database)
        let processes = await ProcessList.load(using: failure.runner).processes
        let lsof = await opened
        // lsof answers 1 with nothing when no process has the file open; anything else is a list it couldn't make.
        guard !processes.isEmpty, lsof.succeeded || (lsof.status == 1 && lsof.stdout.isEmpty) else { return Self.unknown }
        let holders = Set(lsof.stdout.split(whereSeparator: \.isNewline).compactMap { Int32($0) })
        let derivedData = database.firstMatch(of: #/^(.+)/Build/Intermediates\.noindex/XCBuildData/build\.db$/#).map { ProjectLayout.canonicalPath(String($0.1)) }
        let building = processes.filter(Self.isXcodebuild).first { process in
            holders.contains(process.id) || derivedData.map { Self.derivedData(of: process) == $0 } == true
        }
        if let building { return Self.held(by: building) }
        if let other = processes.first(where: { holders.contains($0.id) }) { return Self.heldElsewhere(by: other) }
        return Self.free
    }

    static func isXcodebuild(_ process: ProcessList.Process) -> Bool {
        process.program == "xcodebuild" || process.command.split(separator: " ").first?.hasSuffix("/xcodebuild") == true
    }

    /// The DerivedData an xcodebuild builds into, from its `-derivedDataPath`, spelled as the file system spells it.
    static func derivedData(of process: ProcessList.Process) -> String? {
        process.command.firstMatch(of: #/-derivedDataPath (.+?)(?= -[A-Za-z]|$)/#).map { ProjectLayout.canonicalPath(String($0.1)) }
    }

    /// When nothing holds the database any more.
    static let free = "its build database is locked (\"database is locked\") by another build, and no process holds it now. Build again."

    /// When the processes couldn't be listed: nothing is said about whether one holds it.
    static let unknown = "its build database is locked (\"database is locked\") by another build; xcrew couldn't list the processes to say which."

    /// An xcodebuild holding the database: where it builds for, how long it has run, and how to stop it.
    static func held(by holder: ProcessList.Process) -> String {
        let destination = holder.command.firstMatch(of: #/-destination (.+?)(?= -[A-Za-z]|$)/#).map { ", for \($0.1)" } ?? ""
        return "an xcodebuild holds its build database (\"database is locked\"): pid \(holder.id)\(destination), running \(age(holder.elapsed)). A call stopped partway leaves its xcodebuild running; stopping it frees the database: kill \(holder.id)"
    }

    /// Another process holding it, such as Xcode's build service: a build still going, not one to stop.
    static func heldElsewhere(by holder: ProcessList.Process) -> String {
        let name = holder.program.isEmpty ? "a process" : holder.program
        return "\(name) holds its build database (\"database is locked\"): pid \(holder.id), running \(age(holder.elapsed)), a build still going, in Xcode or another session. The database is free once it ends."
    }

    /// `40 s`, `12 min`, `3 h`, `1 d 2 h`.
    static func age(_ seconds: Int) -> String {
        switch seconds {
        case ..<60: "\(seconds) s"
        case ..<3600: "\(seconds / 60) min"
        case ..<86_400: "\(seconds / 3600) h"
        default: "\(seconds / 86_400) d \(seconds % 86_400 / 3600) h"
        }
    }
}
