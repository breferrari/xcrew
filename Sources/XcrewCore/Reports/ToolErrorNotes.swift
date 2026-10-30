import Foundation

/// MobileBuildMCP's errors that have a way around them, read from a failed result's error entries as MobileBuildMCP
/// 2.7.1 words them (docs/findings.md, *MobileBuildMCP errors with a way around them*).
public enum ToolErrorNotes {
    /// Its screenshot of a simulator with more than one display, which it names none of.
    static let displays = "xcrew: this simulator has more than one display, and MobileBuildMCP's screenshot names none. `xcrun simctl io <udid> enumerate` lists them, and `xcrun simctl io <udid> screenshot --display=<id> <file>` captures one."

    /// An LLDB command under its default debugger backend, which runs none.
    static let debuggerBackend = "xcrew: MobileBuildMCP's default debugger backend, DAP, doesn't run LLDB commands such as `expr`; its CLI backend does. `debuggerBackend: lldb-cli` at the top level of .mobilebuildmcp/config.yaml, or MOBILEBUILDMCP_DEBUGGER_BACKEND=lldb-cli, selects it from the next start of Claude Code."

    /// Each error's start, and its note.
    static let known: [(start: String, note: String)] = [
        ("Failed to capture screenshot: Cannot choose between", displays),
        ("DAP backend does not support LLDB command evaluation", debuggerBackend),
    ]

    /// The notes for a failed result's MobileBuildMCP errors; none for anything else, the Xcode MCP's having no such entries.
    public static func notes(for output: ToolOutput) -> [String] {
        guard output.isError else { return [] }
        let errors = output.reportedErrors.map(\.message)
        return known.filter { known in errors.contains { $0.hasPrefix(known.start) } }.map(\.note)
    }
}
