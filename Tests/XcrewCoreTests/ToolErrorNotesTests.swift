import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// MobileBuildMCP's errors with a way around them: a screenshot of a simulator with two displays, and an LLDB command
/// under the DAP backend (test bed v0.8.3's captures K and N, as MobileBuildMCP 2.7.1 words them).
@Suite struct ToolErrorNotesTests {
    static let twoDisplays = "\n📷 Screenshot\n\nErrors (1):\n\n  ✗ Failed to capture screenshot: Cannot choose between 2 displays. Specify one with --display:\n\n❌ Failed to capture screenshot.\n"
    static let dap = "\n🐛 LLDB Command\n\nErrors (1):\n\n  ✗ DAP backend does not support LLDB command evaluation. Set MOBILEBUILDMCP_DEBUGGER_BACKEND=lldb-cli to use the CLI backend.\n\n❌ Failed to run LLDB command.\n"
    static let displayNote = "xcrew: this simulator has more than one display, and MobileBuildMCP's screenshot names none. `xcrun simctl io <udid> enumerate` lists them, and `xcrun simctl io <udid> screenshot --display=<id> <file>` captures one."
    static let lldbNote = "xcrew: MobileBuildMCP's default debugger backend, DAP, doesn't run LLDB commands such as `expr`; its CLI backend does. `debuggerBackend: lldb-cli` at the top level of .mobilebuildmcp/config.yaml, or MOBILEBUILDMCP_DEBUGGER_BACKEND=lldb-cli, selects it from the next start of Claude Code."

    func notes(_ text: String, server: Server = .mobileBuildMCP, isError: Bool = true) -> [String] {
        ToolErrorNotes.notes(for: ToolOutput(text: text, server: server, isError: isError))
    }

    @Test func aScreenshotOfATwoDisplaySimulatorNamesSimctlsDisplayOption() {
        #expect(notes(Self.twoDisplays) == [Self.displayNote])
    }

    @Test func anLLDBCommandUnderDAPNamesTheCLIBackend() {
        #expect(notes(Self.dap) == [Self.lldbNote])
    }

    /// The words alone, in a result that isn't an error or isn't MobileBuildMCP's, or a test's assertion, aren't the error.
    @Test func theWordsElsewhereHaveNoNote() {
        #expect(notes(Self.twoDisplays, isError: false).isEmpty)
        #expect(notes(Self.dap, server: .xcode).isEmpty)
        #expect(notes("\n🧪 Test\n\nErrors (1):\n\n  ✗ ScreenTests / testPicker: XCTAssertEqual failed: (\"Cannot choose between 2 displays\") is not equal to (\"\")\n").isEmpty)
    }
}
