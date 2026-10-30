import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// An Xcode MCP call whose connection closed, as Claude Code's MCP client words it (`McpError`, code -32000, read from
/// Claude Code 2.1.314's executable): the note names the reconnect.
@Suite struct ClosedConnectionTests {
    static let closed = "MCP error -32000: Connection closed"
    static let note = "xcrew: the Xcode MCP's connection closed, as it does when the selected Xcode changes during a session; /mcp → Reconnect restarts it."

    func report(_ text: String, server: Server, isError: Bool = true) async -> Report {
        await Report.make(kind: .build, output: ToolOutput(text: text, server: server, isError: isError), home: "/home", runner: FakeRunner())
    }

    @Test func anXcodeMCPCallWhoseConnectionClosedNamesTheReconnect() async {
        #expect(await report(Self.closed, server: .xcode).notes.contains(Self.note))
    }

    /// MobileBuildMCP's own, or a result that isn't an error, says nothing of the Xcode MCP's connection.
    @Test func anotherServersOrAResultThatIsNotAnErrorHasNoNote() async {
        #expect(!(await report(Self.closed, server: .mobileBuildMCP).notes.contains(Self.note)))
        #expect(!(await report(Self.closed, server: .xcode, isError: false).notes.contains(Self.note)))
    }
}
