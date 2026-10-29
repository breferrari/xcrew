import Foundation
import Testing

/// Runs the real `scripts/stable-check.sh` with how GitHub compares the latest release's tag with `stable`, the branch
/// installs follow.
@Suite struct StableCheckScriptTests {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// 2026-10-29T18:00:00Z.
    let released: Int = 1_793_296_800

    func check(_ status: String, hoursLater: Int) async throws -> (status: Int32, errors: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [repository.appending(path: "scripts/stable-check.sh").path, "v0.8.3", "2026-10-29T18:00:00Z", String(released + hoursLater * 3600), status]
        process.standardInput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try await ShimTests.runToEnd(process)
        return (process.terminationStatus, String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    @Test func stableOnTheLatestReleasePasses() async throws {
        #expect(try await check("identical", hoursLater: 48).status == 0)
    }

    /// The release workflow moves `stable` before it publishes; a day covers a release still settling many times over.
    @Test func stableBehindForADayFailsNamingTheFix() async throws {
        #expect(try await check("behind", hoursLater: 2).status == 0)
        let late = try await check("behind", hoursLater: 25)
        #expect(late.status == 1)
        #expect(late.errors == "installs follow stable, which is behind v0.8.3, released at 2026-10-29T18:00:00Z: rerun v0.8.3's release workflow, which moves stable\n")
    }

    /// Commits no release has mean installs run unreleased code, which waits for nothing.
    @Test func stableWithUnreleasedCommitsFailsAtOnce() async throws {
        for status in ["ahead", "diverged"] {
            let now = try await check(status, hoursLater: 1)
            #expect(now.status == 1)
            #expect(now.errors == "stable is \(status) of v0.8.3: installs run code no release has. Release it, or have the repository's owner reset stable to v0.8.3, since its ruleset refuses a rewind\n")
        }
    }

    @Test func anAnswerItCantReadFails() async throws {
        let unknown = try await check("", hoursLater: 1)
        #expect(unknown.status == 1)
        #expect(unknown.errors == "couldn't compare stable with v0.8.3 (GitHub answered '')\n")
    }
}
