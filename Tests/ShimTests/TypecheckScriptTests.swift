import Foundation
import Testing

/// Runs the real `scripts/typecheck.sh` from a copy of the repository with no API types laid.
@Suite struct TypecheckScriptTests {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func withoutTypesItNamesTheInteractiveSession() async throws {
        let script = FileManager.default.temporaryDirectory.appending(path: "xcrew-typecheck-\(UUID().uuidString)/scripts/typecheck.sh")
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: repository.appending(path: "scripts/typecheck.sh"), to: script)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        process.standardInput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try await ShimTests.runToEnd(process)
        #expect(process.terminationStatus == 1)
        #expect(String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) == "typecheck: no API types yet. Run 'claude --plugin-dir .' here once, interactively (claude -p doesn't write them), then rerun.\n")
    }
}
