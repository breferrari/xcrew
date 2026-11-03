import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// What a session reported to xcrew, and the two checks that read it for the session the doctor runs in.
@Suite struct SessionStampTests {
    static let session = "5f0c1a2b-0000-4000-8000-000000000001"

    func context(_ stamp: SessionStamp?, project: Project = .temporary(), session: String? = Self.session) -> CheckContext {
        let context = CheckContext.fake(project: project, environment: session.map { ["CLAUDE_CODE_SESSION_ID": $0] } ?? [:])
        if let stamp { SessionStamp.record(Self.session, on: context.machine) { $0 = stamp } }
        return context
    }

    @Test func aStampIsKeptReadAndRemoved() {
        let machine = context(nil).machine
        SessionStamp.record(Self.session, on: machine) { $0.briefing = "0.12.0" }
        SessionStamp.record(Self.session, on: machine) { $0.mod = "0.12.0" }
        #expect(SessionStamp.read(Self.session, on: machine) == SessionStamp(briefing: "0.12.0", mod: "0.12.0"))
        SessionStamp.remove(Self.session, on: machine)
        #expect(SessionStamp.read(Self.session, on: machine) == nil)
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
}
