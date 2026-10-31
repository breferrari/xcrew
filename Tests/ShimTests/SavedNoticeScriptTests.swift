import Foundation
import Testing

/// Runs the real `scripts/saved-notice.sh` against a stand-in for Claude Code's executable, with a `bin/xcrew` that
/// keeps the notice it's handed and, for one in today's shape, answers as `xcrew report` does when it reads the saved file
/// back. Whether the real `xcrew report` reads it is the canary's to say, against the real executable.
@Suite struct SavedNoticeScriptTests {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The notice as Claude Code 2.1.312 builds it, beside the same words in its bytecode's string table.
    static let current = "\u{0}\u{1}Output has been saved to \u{0}\u{7}\u{0}Format: \u{0}" +
        "r: result (${h!==void 0?`${n} characters across lines`:`${n} characters`}) exceeds maximum allowed tokens. Output has been saved to ${e}.\nFormat: ${r}\n`,D=y===void 0?\"\":`"

    func check(_ executable: String) async throws -> (status: Int32, errors: String, notice: String) {
        let root = FileManager.default.temporaryDirectory.appending(path: "xcrew-notice-\(UUID().uuidString)")
        // A stand-in for the test bed's capture: the stand-in xcrew never reads what was saved.
        for folder in ["scripts", "bin", "testbed/captures/raw"] {
            try FileManager.default.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true)
        }
        try FileManager.default.copyItem(at: repository.appending(path: "scripts/saved-notice.sh"), to: root.appending(path: "scripts/saved-notice.sh"))
        try #"{"structuredContent":{"schema":"mobilebuildmcp.output.test-result"}}"#.write(to: root.appending(path: "testbed/captures/raw/serial.json"), atomically: true, encoding: .utf8)
        let xcrew = root.appending(path: "bin/xcrew")
        try """
        #!/bin/sh
        tee "$(dirname "$0")/../notice.txt" | perl -0777 -ne 'print "{\\"result\\":\\"the full result is in $1\\"}" if /saved to (\\S+)\\.\\n/'
        """.write(to: xcrew, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: xcrew.path)
        try Data(executable.utf8).write(to: root.appending(path: "claude"))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [root.appending(path: "scripts/saved-notice.sh").path, root.appending(path: "claude").path]
        process.environment = ProcessInfo.processInfo.environment.merging(["XCREW_TESTBED": root.appending(path: "testbed").path]) { _, new in new }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try await ShimTests.runToEnd(process)
        let notice = (try? String(contentsOf: root.appending(path: "notice.txt"), encoding: .utf8)) ?? ""
        return (process.terminationStatus, String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self), notice)
    }

    @Test func theNoticeAsClaudeCodeWritesItIsReadBack() async throws {
        let result = try await check(Self.current)
        #expect(result.status == 0)
        #expect(try #/Error: result \(121,948 characters\) exceeds maximum allowed tokens\. Output has been saved to \/\S+\/tool-results\/mcp-test_sim-1\.txt\.\nFormat: JSON/#.wholeMatch(in: result.notice) != nil)
    }

    @Test func aNoticeWithoutTheWordsXcrewLooksForFails() async throws {
        let result = try await check(Self.current.replacingOccurrences(of: "Output has been saved to", with: "Output was saved to"))
        #expect(result.status == 1)
        #expect(result.errors == "Claude Code's executable has no 'Output has been saved to ${…}' notice: xcrew finds the saved file by its path, so check that the new notice still names it, then update the words scripts/saved-notice.sh looks for\n")
    }

    @Test func anExecutableWithTheWordsButNoTemplateSaysSo() async throws {
        let result = try await check("\u{0}\u{1}Output has been saved to \u{0}\u{7}\u{0}Format: \u{0}")
        #expect(result.status == 1)
        #expect(result.errors == "Claude Code's executable has the words 'Output has been saved to' but no template with them as text, so this check can't read the notice: rework scripts/saved-notice.sh\n")
    }

    @Test func aNoticeXcrewNoLongerReadsBackFails() async throws {
        let result = try await check(Self.current.replacingOccurrences(of: "${e}.\nFormat: ${r}\n", with: "${e} (${r})"))
        #expect(result.status == 1)
        #expect(result.errors.hasPrefix("xcrew didn't read back a result saved under Claude Code's notice, which now reads \"Error: result (121,948 characters) exceeds maximum allowed tokens. Output has been saved to /"))
        #expect(result.errors.hasSuffix("/tool-results/mcp-test_sim-1.txt (JSON)\": xcrew finds the saved file by an existing path in a tool-results folder, so check that the notice still names one\n"))
    }
}
