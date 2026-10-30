import Foundation

/// An Xcode MCP call that failed because its connection closed, as Claude Code's MCP client words it
/// (`MCP error -32000: Connection closed`). The bridge Claude Code started belongs to the Xcode selected then, and
/// closes when another is selected (docs/findings.md, *The Xcode MCP after an Xcode switch*).
public enum ClosedConnection {
    public static let note = "xcrew: the Xcode MCP's connection closed, as it does when the selected Xcode changes during a session; /mcp → Reconnect restarts it."

    /// Claude Code's whole error for a call whose connection closed: a failure that says "Connection closed" of its
    /// own, as a networking test's does, isn't one.
    static let error = "MCP error -32000: Connection closed"

    /// The note for an Xcode MCP error that is Claude Code's for a closed connection; none for anything else.
    public static func notes(for output: ToolOutput) -> [String] {
        output.server == .xcode && output.isError && output.text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(error) ? [note] : []
    }
}
