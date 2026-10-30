import Foundation
import Testing

@testable import XcrewCore
import XcrewTestSupport

/// A build or test call that answers with no outcome, as a call Claude moved to the background answers with a handle.
/// Claude Code's mod docs give no shape for that handle, so a text in no shape either server uses stands for it.
@Suite struct UnreadResultTests {
    static let handle = "Task bg-1 is running in the background; its result will arrive as a notification."

    func report(_ text: String, server: Server, kind: Report.Kind = .build, isError: Bool = false) async -> Report {
        await Report.make(kind: kind, output: ToolOutput(text: text, server: server, isError: isError), home: "/home", runner: FakeRunner())
    }

    @Test func aResultInNoShapeIsUnread() async {
        #expect(await report(Self.handle, server: .mobileBuildMCP).isUnread == true)
        #expect(await report(Self.handle, server: .xcode, kind: .test).isUnread == true)
    }

    /// An error is an outcome, and a run (an app launch) may well answer with nothing to read.
    @Test func anErrorOrARunIsNoUnreadResult() async {
        #expect(await report(Self.handle, server: .mobileBuildMCP, isError: true).isUnread == nil)
        #expect(await report(Self.handle, server: .mobileBuildMCP, kind: .run).isUnread == nil)
    }

    @Test func aResultThatSaysAnOutcomeIsRead() async {
        let succeeded = #"{"schema":"mobilebuildmcp.output.build-result","data":{"summary":{"status":"SUCCEEDED"}}}"#
        #expect(await report(succeeded, server: .mobileBuildMCP).isUnread == nil)
    }
}
