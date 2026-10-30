import Foundation
import Testing

/// Runs the real `scripts/background-texts.sh` against a stand-in for Claude Code's executable, with a `bin/xcrew` that
/// keeps what it's handed and answers as `xcrew report` does for a handle and a notification in today's shape. Whether
/// the real `xcrew report` reads them is the canary's to say, against the real executable.
@Suite struct BackgroundTextsScriptTests {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The handle's and the notification's templates as Claude Code 2.1.314 carries them.
    static let current = #"hu="task-notification",AF="task-id",x3="tool-use-id",HU="task-type";var eje="output-file",Bw="status",x_="summary";"# +
        #"text:`MCP tool "${Hoe(e,n)}" started server-side task ${u}. It was moved to the background as task ${s} and keeps running on the server; you can keep working in the meantime. ${C}`}]}"# +
        "return _i({taskId:e.registryId,status:e.status,summary:Bt(n),body:`\n<result>\n${I1e(c,Zye()-o.length)}${o}\n</result>`})}"

    /// How the stand-in `bin/xcrew` answers: today's `xcrew report` for a handle and a notification.
    static let reads = #"print "{\"backgroundTask\":\"$1\"}" if /moved to the background as task ([A-Za-z0-9_-]+)/; print "{\"ok\":false}" if /<status>completed<\/status>.*<result>\n.+\n<\/result>/s"#

    func check(_ executable: String, xcrewReads: String = reads) async throws -> (status: Int32, errors: String, handed: String) {
        let root = FileManager.default.temporaryDirectory.appending(path: "xcrew-background-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = "Tests/XcrewCoreTests/Fixtures/Reports/mobileBuildFailed.txt"
        for folder in ["scripts", "bin", "Tests/XcrewCoreTests/Fixtures/Reports"] {
            try FileManager.default.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true)
        }
        try FileManager.default.copyItem(at: repository.appending(path: "scripts/background-texts.sh"), to: root.appending(path: "scripts/background-texts.sh"))
        try FileManager.default.copyItem(at: repository.appending(path: fixture), to: root.appending(path: fixture))
        let xcrew = root.appending(path: "bin/xcrew")
        try """
        #!/bin/sh
        tee -a "$(dirname "$0")/../handed.txt" | perl -0777 -ne '\(xcrewReads)'
        """.write(to: xcrew, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: xcrew.path)
        try Data(executable.utf8).write(to: root.appending(path: "claude"))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [root.appending(path: "scripts/background-texts.sh").path, root.appending(path: "claude").path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try await ShimTests.runToEnd(process)
        let handed = (try? String(contentsOf: root.appending(path: "handed.txt"), encoding: .utf8)) ?? ""
        return (process.terminationStatus, String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self), handed)
    }

    @Test func theTextsAsClaudeCodeWritesThemAreRead() async throws {
        let result = try await check(Self.current)
        #expect(result.status == 0, "\(result.errors)")
        #expect(result.handed.hasPrefix(#"MCP tool "plugin:xcrew:MobileBuildMCP/build_sim" is still running after 120s. It was moved to the background as task canary7 and keeps running on the server; "#))
        #expect(result.handed.contains("<task-notification>\n<task-id>canary7</task-id>\n<status>completed</status>\n"))
    }

    @Test func aHandleWithoutTheWordsXcrewLooksForFails() async throws {
        let result = try await check(Self.current.replacingOccurrences(of: "It was moved to the background as task", with: "It now runs in the background as task"))
        #expect(result.status == 1)
        #expect(result.errors == "Claude Code's executable has no 'It was moved to the background as task ${…}' handle: xcrew finds a backgrounded call's task by those words, so read the new handle and update Report.backgroundTask and scripts/background-texts.sh\n")
    }

    @Test func aNotificationWithoutItsResultLinesFails() async throws {
        let result = try await check(Self.current.replacingOccurrences(of: "\n</result>`", with: "</result>`"))
        #expect(result.status == 1)
        #expect(result.errors == "Claude Code's executable no longer builds a task's notification with the task-id and status tags and its result between <result> lines: xcrew reads a backgrounded call's result there, so read the new notification and update TaskNotification and scripts/background-texts.sh\n")
    }

    @Test func aHandleXcrewNoLongerReadsFails() async throws {
        let result = try await check(Self.current, xcrewReads: #"print "{}""#)
        #expect(result.status == 1)
        #expect(result.errors.hasPrefix("xcrew didn't read the task in Claude Code's handle, which now reads \"MCP tool"))
    }
}
