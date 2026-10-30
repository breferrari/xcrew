import Foundation

/// The errors of a failed tool result that have a way around them: a closed Xcode MCP connection (`ClosedConnection`),
/// and MobileBuildMCP's, read from its error entries as 2.7.1 words them (docs/findings.md, *MobileBuildMCP errors with
/// a way around them*).
public enum ToolErrorNotes {
    /// Each error's start, and its note: a screenshot of a simulator with more than one display, which it names none of,
    /// and an LLDB command under its default debugger backend, which runs none.
    static let known: [(start: String, note: String)] = [
        ("Failed to capture screenshot: Cannot choose between", "xcrew: this simulator has more than one display, and MobileBuildMCP's screenshot names none. `xcrun simctl io <udid> enumerate` lists them, and `xcrun simctl io <udid> screenshot --display=<id> <file>` captures one."),
        ("DAP backend does not support LLDB command evaluation", "xcrew: MobileBuildMCP's default debugger backend, DAP, doesn't run LLDB commands such as `expr`; its CLI backend does. `debuggerBackend: lldb-cli` at the top level of .mobilebuildmcp/config.yaml, or MOBILEBUILDMCP_DEBUGGER_BACKEND=lldb-cli, selects it from the next start of Claude Code."),
    ]

    /// The notes for a failed result: a closed Xcode MCP connection's, and those of its MobileBuildMCP errors, the Xcode
    /// MCP's having no such entries. Every reader of a tool's result asks here.
    public static func notes(for output: ToolOutput) -> [String] {
        guard output.isError else { return [] }
        let errors = output.reportedErrors.map(\.message)
        return ClosedConnection.notes(for: output) + known.filter { known in errors.contains { $0.hasPrefix(known.start) } }.map(\.note)
    }
}
