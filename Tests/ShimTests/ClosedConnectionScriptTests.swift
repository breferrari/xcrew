import Foundation
import Testing

/// Runs the real `scripts/closed-connection.sh` against a stand-in for Claude Code's executable, with a `bin/xcrew` that
/// keeps what it's handed and answers as `xcrew note` does for a closed connection. Whether the real `xcrew note` reads
/// it is the canary's to say, against the real executable.
@Suite struct ClosedConnectionScriptTests {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The MCP client's error and its code as Claude Code 2.1.314 carries them.
    static let current = #"class ea extends Error{constructor(t,c,m){super(`MCP error ${t}: ${c}`);this.code=t}}let t=ea.fromError(ga.ConnectionClosed,"Connection closed");"#

    func check(_ executable: String, xcrewNotes: Bool = true) async throws -> (status: Int32, errors: String, handed: String) {
        let root = FileManager.default.temporaryDirectory.appending(path: "xcrew-closed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["scripts", "bin"] { try FileManager.default.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true) }
        try FileManager.default.copyItem(at: repository.appending(path: "scripts/closed-connection.sh"), to: root.appending(path: "scripts/closed-connection.sh"))
        let xcrew = root.appending(path: "bin/xcrew")
        try """
        #!/bin/sh
        tee "$(dirname "$0")/../handed.txt" | perl -0777 -ne 'print "{\\"notes\\":[\\"/mcp\\"]}" if /Connection closed/ && \(xcrewNotes ? 1 : 0)'
        """.write(to: xcrew, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: xcrew.path)
        try Data(executable.utf8).write(to: root.appending(path: "claude"))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [root.appending(path: "scripts/closed-connection.sh").path, root.appending(path: "claude").path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try await ShimTests.runToEnd(process)
        let handed = (try? String(contentsOf: root.appending(path: "handed.txt"), encoding: .utf8)) ?? ""
        return (process.terminationStatus, String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self), handed)
    }

    @Test func theErrorAsClaudeCodeWordsItIsNoted() async throws {
        let result = try await check(Self.current)
        #expect(result.status == 0, "\(result.errors)")
        #expect(result.handed == "MCP error -32000: Connection closed")
    }

    @Test func anExecutableWithoutTheClosedConnectionFails() async throws {
        let result = try await check(Self.current.replacingOccurrences(of: #""Connection closed""#, with: #""Disconnected""#))
        #expect(result.status == 1)
        #expect(result.errors.hasPrefix("Claude Code's executable no longer raises an MCP error \"Connection closed\""))
    }

    @Test func anErrorXcrewNoLongerNotesFails() async throws {
        let result = try await check(Self.current, xcrewNotes: false)
        #expect(result.status == 1)
        #expect(result.errors == "xcrew didn't note an Xcode MCP call whose connection closed, which Claude Code now words \"MCP error -32000: Connection closed\": check ClosedConnection against it\n")
    }
}
