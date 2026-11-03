import Foundation
import Testing

/// Runs the real `scripts/stable-check.sh` with how GitHub compares the latest release's tag with `stable`, the branch
/// installs follow, and how that tag's release run stands: the check reads state, never the clock.
@Suite struct StableCheckScriptTests {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func check(_ status: String, run: String = "completed") async throws -> (status: Int32, errors: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [repository.appending(path: "scripts/stable-check.sh").path, "v0.8.3", run, status]
        process.standardInput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try await ShimTests.runToEnd(process)
        return (process.terminationStatus, String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    @Test func stableOnTheLatestReleasePasses() async throws {
        #expect(try await check("identical").status == 0)
    }

    /// The release workflow moves `stable`: behind while its run still goes is no failure, and behind once it has
    /// finished is, naming the fix.
    @Test func stableBehindOnceTheReleaseRunEndedFailsNamingTheFix() async throws {
        for run in ["queued", "in_progress"] { #expect(try await check("behind", run: run).status == 0) }
        let ended = try await check("behind")
        #expect(ended.status == 1)
        #expect(ended.errors == "installs follow stable, which is behind v0.8.3, though its release run has ended: rerun v0.8.3's release workflow, which moves stable\n")
    }

    /// Commits no release has mean installs run unreleased code, which waits for nothing.
    @Test func stableWithUnreleasedCommitsFailsAtOnce() async throws {
        for status in ["ahead", "diverged"] {
            let now = try await check(status)
            #expect(now.status == 1)
            #expect(now.errors == "stable is \(status) of v0.8.3: installs run code no release has. Release it, or have the repository's owner reset stable to v0.8.3, since its ruleset refuses a rewind\n")
        }
    }

    /// Behind, with no release run status read, can't be told from a run still going: that fails, saying why.
    @Test func stableBehindWithTheRunUnreadFails() async throws {
        let unread = try await check("behind", run: "")
        #expect(unread.status == 1)
        #expect(unread.errors == "stable is behind v0.8.3, and its release run's status couldn't be read: gh run list --workflow release.yml --branch v0.8.3 reads it\n")
    }

    @Test func anAnswerItCantReadFails() async throws {
        let unknown = try await check("")
        #expect(unknown.status == 1)
        #expect(unknown.errors == "couldn't compare stable with v0.8.3 (GitHub answered '')\n")
    }
}
