import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// What a session reported to xcrew, and the two checks that read it for the session the doctor runs in.
@Suite struct SessionStampTests {
    static let session = "5f0c1a2b-0000-4000-8000-000000000001"

    func context(_ stamp: SessionStamp?, project: Project = .temporary(), session: String? = Self.session) -> CheckContext {
        let context = CheckContext.fake(project: project, environment: session.map { ["CLAUDE_CODE_SESSION_ID": $0] } ?? [:])
        if let briefing = stamp?.briefing { SessionStamp.record(Self.session, on: context.machine, .briefing, version: briefing) }
        if let mod = stamp?.mod { SessionStamp.record(Self.session, on: context.machine, .mod, version: mod) }
        return context
    }

    @Test func aStampIsKeptReadAndRemoved() {
        let machine = context(nil).machine
        SessionStamp.record(Self.session, on: machine, .briefing, version: "0.12.0")
        SessionStamp.record(Self.session, on: machine, .mod, version: "0.12.0")
        #expect(SessionStamp.read(Self.session, on: machine) == SessionStamp(briefing: "0.12.0", mod: "0.12.0"))
        SessionStamp.remove(Self.session, on: machine)
        #expect(SessionStamp.read(Self.session, on: machine) == nil)
    }

    /// The start hook and the mod's doctor read write a session's stamp at once as it starts, each its own fact: one
    /// writer never rewrites a file that holds the other's, so neither can put back an older view of it.
    @Test func oneWriterNeverRewritesTheOthersFact() throws {
        let machine = context(nil).machine
        SessionStamp.record(Self.session, on: machine, .mod, version: "mod-2")
        let sessions = machine.cacheFolder.appending(path: "sessions")
        let files = { (FileManager.default.enumerator(at: sessions, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []).filter { !$0.hasDirectoryPath } }
        for file in files() { try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: file.path) }
        SessionStamp.record(Self.session, on: machine, .briefing, version: "briefing-1")
        let holdingMod = files().filter { (try? String(contentsOf: $0, encoding: .utf8))?.contains("mod-2") == true }
        #expect(!holdingMod.isEmpty)
        for file in holdingMod {
            #expect(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == Date(timeIntervalSince1970: 0), "\(file.lastPathComponent) was rewritten")
        }
        #expect(SessionStamp.read(Self.session, on: machine) == SessionStamp(briefing: "briefing-1", mod: "mod-2"))
    }

    /// A session open across an upgrade keeps what it reported to the older xcrew, in the one file it kept, until its own
    /// writer reports again; ending the session removes both.
    @Test func anOlderXcrewsStampIsReadUntilEachWriterReportsAgain() throws {
        let machine = context(nil).machine
        let older = machine.cacheFolder.appending(path: "sessions/\(Self.session).json")
        try FileManager.default.createDirectory(at: older.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"briefing":"0.13.1","mod":"0.13.1"}"#.utf8).write(to: older)
        SessionStamp.record(Self.session, on: machine, .mod, version: "0.14.0")
        #expect(SessionStamp.read(Self.session, on: machine) == SessionStamp(briefing: "0.13.1", mod: "0.14.0"))
        SessionStamp.remove(Self.session, on: machine)
        #expect(SessionStamp.read(Self.session, on: machine) == nil)
        #expect(!FileManager.default.fileExists(atPath: older.path))
    }

    /// A session's first record removes the stamps no session end removed for longer than they're kept, a session's
    /// folder or an older xcrew's file, and leaves the newer ones: one left 15 days ago goes, one left 13 days ago stays.
    @Test func aSessionsFirstRecordRemovesTheStampsLeftTooLong() throws {
        let given = context(nil).machine
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let machine = Machine(environment: given.environment, home: given.home, runner: given.runner, processID: given.processID, now: { now }, files: RootedFiles(roots: [given.home]))
        let sessions = machine.cacheFolder.appending(path: "sessions")
        SessionStamp.record("old", on: machine, .mod, version: "0.13.0")
        SessionStamp.record("recent", on: machine, .mod, version: "0.13.0")
        try Data("{}".utf8).write(to: sessions.appending(path: "older.json"))
        let ago = { (days: Double) in now.addingTimeInterval(-days * 24 * 3600) }
        try FileManager.default.setAttributes([.modificationDate: ago(15)], ofItemAtPath: sessions.appending(path: "old").path)
        try FileManager.default.setAttributes([.modificationDate: ago(15)], ofItemAtPath: sessions.appending(path: "older.json").path)
        try FileManager.default.setAttributes([.modificationDate: ago(13)], ofItemAtPath: sessions.appending(path: "recent").path)
        SessionStamp.record(Self.session, on: machine, .briefing, version: "0.14.0")
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: sessions.path)) == ["recent", Self.session])
    }

    /// From a terminal Claude Code names no session: both checks skip.
    @Test func fromATerminalBothChecksSkip() async {
        let context = context(SessionStamp(briefing: "0.0.1"), session: nil)
        #expect(await BriefingCurrentCheck().run(context).status == .skip)
        #expect(await ModLoadedCheck().run(context).status == .skip)
    }

    @Test func rulesFromTheRunningVersionPass() async {
        #expect(await BriefingCurrentCheck().run(context(SessionStamp(briefing: XcrewVersion.current))) == .pass("the running xcrew's"))
    }

    /// A plugin updated in an open session, `/reload-plugins` included, keeps the rules its start hook gave.
    @Test func rulesFromAnOlderVersionAskForARestart() async {
        #expect(await BriefingCurrentCheck().run(context(SessionStamp(briefing: "0.11.0"))) == .warn("this session's rules are xcrew 0.11.0's, and xcrew \(XcrewVersion.current) is running: restart Claude Code to load \(XcrewVersion.current)'s"))
    }

    @Test func aModThatReportedPasses() async {
        #expect(await ModLoadedCheck().run(context(SessionStamp(briefing: XcrewVersion.current, mod: XcrewVersion.current))) == .pass("reported in this session"))
    }

    /// The start hook reported and the mod hasn't: it isn't loaded, or the doctor ran before its first read landed.
    @Test func aModThatHasntReportedWarnsAndSaysItMayBeStarting() async {
        let unreported = "xcrew's mod hasn't reported in this session: it isn't loaded, so its notes, its tools and the line above the prompt are off, or it's still starting and the doctor ran first"
        #expect(await ModLoadedCheck().run(context(SessionStamp(briefing: XcrewVersion.current))) == .warn("\(unreported): restart Claude Code"))
        let mcs = Project.temporary()
        mcs.write(#"{"configuredPacks":["xcrew"],"mcsVersion":"2026.10.30"}"#, to: ".claude/.mcs-project")
        #expect(await ModLoadedCheck().run(context(SessionStamp(briefing: XcrewVersion.current), project: mcs)) == .warn("\(unreported): with mcs, update it to \(ModLoadedCheck.minMCSVersion) or later and run mcs sync"))
    }

    /// No stamp at all, as where the start hook was passed over: nothing to say.
    @Test func withoutAStampBothChecksSkip() async {
        #expect(await BriefingCurrentCheck().run(context(nil)).status == .skip)
        #expect(await ModLoadedCheck().run(context(nil)).status == .skip)
    }

    /// A stamp's file name keeps an id's ASCII letters, digits, `-` and `_`, and is `_` with none: the shim names it so
    /// for a session's end, which runs no CLI (bin/xcrew's `hook_session`).
    @Test func aStampsNameKeepsTheASCIIOfTheIdAsTheShimDoes() {
        #expect(SessionStamp.fileName("0b1c2d3e-4f50_x") == "0b1c2d3e-4f50_x")
        #expect(SessionStamp.fileName("été-1/../2") == "t-12")
        #expect(SessionStamp.fileName("é") == "_")
    }
}
