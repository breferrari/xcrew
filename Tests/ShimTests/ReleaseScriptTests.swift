import Foundation
import Testing
import XcrewTestSupport

/// Runs the real `scripts/release.sh` in a throwaway clone of a throwaway origin, with a stand-in `gh` that answers from
/// files the test writes and records what it was asked, and a stand-in `swift`: nothing reaches GitHub.
@Suite struct ReleaseScriptTests {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let base: URL
    let origin: URL
    let clone: URL
    /// What the stand-in `gh` answers from, a file a question: `pr` holds the release pull request's number once it's
    /// opened, `state` its `state mergeStateStatus`, `view-fails` a line `gh pr view` fails with instead.
    let state: URL

    init() throws {
        base = FileManager.default.temporaryDirectory.appending(path: "xcrew-release-\(UUID().uuidString)")
        origin = base.appending(path: "origin.git")
        clone = base.appending(path: "clone")
        state = base.appending(path: "gh")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        try write("""
        #!/bin/sh
        echo "$*" >> "\(state.path)/asked"
        case "$1 $2" in
          "pr list")
            case "$*" in
              *--head*)
                if [ -f "\(state.path)/list-fails" ]; then echo "HTTP 502: Bad Gateway" >&2; exit 1; fi
                cat "\(state.path)/pr" 2>/dev/null || true ;;
            esac ;;
          "pr create") echo 7 > "\(state.path)/pr"; echo "https://github.example/pull/7" ;;
          "pr merge") ;;
          "pr update-branch") if [ -f "\(state.path)/update-fails" ]; then echo "HTTP 502: Bad Gateway" >&2; exit 1; fi ;;
          "pr view")
            if [ -f "\(state.path)/view-fails" ]; then cat "\(state.path)/view-fails" >&2; rm "\(state.path)/view-fails"; exit 1; fi
            case "$*" in
              *autoMergeRequest*)
                if [ -f "\(state.path)/auto-fails" ]; then echo "HTTP 502: Bad Gateway" >&2; exit 1; fi
                if [ -f "\(state.path)/auto-off" ]; then echo off; else echo on; fi ;;
              *)
                # A queue of states, one a poll, the last kept.
                if [ -f "\(state.path)/states" ] && [ "$(wc -l < "\(state.path)/states")" -gt 1 ]; then
                  head -n 1 "\(state.path)/states" > "\(state.path)/state"; sed -i '' 1d "\(state.path)/states"
                elif [ -f "\(state.path)/states" ]; then cp "\(state.path)/states" "\(state.path)/state"; fi
                cat "\(state.path)/state" ;;
            esac
            # Merges on the poll the test asked for, as GitHub's auto-merge would.
            if [ -f "\(state.path)/merges" ] && grep -q MERGED "\(state.path)/state"; then
              git --git-dir "\(origin.path)" update-ref refs/heads/main "refs/heads/$(cat "\(state.path)/merges")"
              rm "\(state.path)/merges"
            fi ;;
          "pr checks")
            if [ -f "\(state.path)/checks-fail" ]; then echo "HTTP 502: Bad Gateway" >&2; rm "\(state.path)/checks-fail"; exit 1; fi
            if [ -f "\(state.path)/no-checks" ]; then echo "no checks reported on the 'release-0.2.0' branch" >&2; exit 1; fi ;;
          "run list") echo 11 ;;
          "run view") echo success ;;
          "repo view") echo owner/xcrew ;;
          "api "*) echo identical ;;
          "release view") echo "https://github.example/releases/v0.2.0" ;;
        esac
        """, to: base.appending(path: "fakebin/gh"), executable: true)
        try write("#!/bin/sh\nexit 0\n", to: base.appending(path: "fakebin/swift"), executable: true)
        // Polls go round without waiting: the test, not the clock, says when the state changes.
        try write("#!/bin/sh\nexit 0\n", to: base.appending(path: "fakebin/sleep"), executable: true)
    }

    func write(_ text: String, to url: URL, executable: Bool = false) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
    }

    @discardableResult
    func sh(_ script: String, in folder: URL? = nil) async throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.currentDirectoryURL = folder ?? base
        process.environment = [
            "PATH": "\(base.appending(path: "fakebin").path):/usr/bin:/bin",
            "HOME": base.path, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com",
        ]
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try await ShimTests.runToEnd(process)
        return (process.terminationStatus, String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    /// A repository with what the release script reads and edits, on `main` in the origin.
    func origin(version: String = "0.1.0") async throws {
        try await sh("git init -q --bare -b main '\(origin.path)' && git clone -q '\(origin.path)' '\(clone.path)'")
        try write("{\n  \"version\": \"\(version)\"\n}\n", to: clone.appending(path: ".claude-plugin/plugin.json"))
        try write("enum XcrewVersion { static let current = \"\(version)\" }\n", to: clone.appending(path: "Sources/XcrewCore/XcrewVersion.swift"))
        try write("# Changelog\n\n## Unreleased\n\n- a change\n", to: clone.appending(path: "CHANGELOG.md"))
        try write("#!/bin/sh\nexit 0\n", to: clone.appending(path: "scripts/distribution.sh"), executable: true)
        try FileManager.default.copyItem(at: repository.appending(path: "scripts/release.sh"), to: clone.appending(path: "scripts/release.sh"))
        try await sh("git add -A && git commit -qm start && git push -q origin main", in: clone)
    }

    func release() async throws -> (status: Int32, output: String) {
        try await sh("scripts/release.sh 0.2.0", in: clone)
    }

    /// A run stopped after it opened the release pull request leaves its branch pushed: run again, it goes on from that
    /// pull request rather than making the release commit again, which the pushed branch would refuse.
    @Test func aRerunGoesOnFromTheReleasePullRequestItOpened() async throws {
        try await origin()
        try "CLOSED \n".write(to: state.appending(path: "state"), atomically: true, encoding: .utf8)
        let stopped = try await release()
        #expect(stopped.status == 1 && stopped.output.contains("#7 was closed"), "\(stopped.output)")
        try "MERGED CLEAN\n".write(to: state.appending(path: "state"), atomically: true, encoding: .utf8)
        try "release-0.2.0\n".write(to: state.appending(path: "merges"), atomically: true, encoding: .utf8)
        let again = try await release()
        #expect(again.status == 0, "\(again.output)")
        #expect(again.output.contains("release: #7 is 0.2.0's release pull request; going on from its merge"), "\(again.output)")
        let asked = try String(contentsOf: state.appending(path: "asked"), encoding: .utf8)
        #expect(asked.components(separatedBy: "pr create").count == 2, "opened a second release pull request")
    }

    /// While it waits it says the state when it changes, and once that auto-merge is off, each with the command to use.
    @Test func theStateIsSaidWhenItChangesAndAutoMergeOffOnce() async throws {
        try await origin()
        try "OPEN BLOCKED\nOPEN BLOCKED\nOPEN BLOCKED\nMERGED CLEAN\n".write(to: state.appending(path: "states"), atomically: true, encoding: .utf8)
        try "release-0.2.0\n".write(to: state.appending(path: "merges"), atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: state.appending(path: "auto-off").path, contents: nil)
        let run = try await release()
        #expect(run.status == 0, "\(run.output)")
        #expect(run.output.components(separatedBy: "release: waiting for #7 to merge (OPEN BLOCKED, 0 checks pending; gh pr checks 7 lists them)").count == 2, "\(run.output)")
        #expect(run.output.components(separatedBy: "release: auto-merge is off on #7, so it won't merge by itself: gh pr merge 7 --auto --squash turns it on").count == 2, "\(run.output)")
    }

    /// Whether a release pull request is open can't be read: the run stops, saying why, rather than making the release
    /// commit again over the branch of one that may be open.
    @Test func aReleasePullRequestItCantLookUpStopsTheRun() async throws {
        try await origin()
        FileManager.default.createFile(atPath: state.appending(path: "list-fails").path, contents: nil)
        try "CLOSED \n".write(to: state.appending(path: "state"), atomically: true, encoding: .utf8)
        let run = try await release()
        #expect(run.status == 1, "\(run.output)")
        #expect(run.output.contains("release: couldn't tell whether 0.2.0's release pull request is open (HTTP 502: Bad Gateway); gh pr list --head release-0.2.0 reads it"), "\(run.output)")
        let asked = (try? String(contentsOf: state.appending(path: "asked"), encoding: .utf8)) ?? ""
        #expect(!asked.contains("pr create"))
    }

    /// Checks that can't be read are said, with the command that reads them, rather than read as none pending.
    @Test func checksThatCantBeReadAreSaid() async throws {
        try await origin()
        try "OPEN BLOCKED\nMERGED CLEAN\n".write(to: state.appending(path: "states"), atomically: true, encoding: .utf8)
        try "release-0.2.0\n".write(to: state.appending(path: "merges"), atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: state.appending(path: "checks-fail").path, contents: nil)
        let run = try await release()
        #expect(run.status == 0, "\(run.output)")
        #expect(run.output.contains("release: couldn't read #7's checks (HTTP 502: Bad Gateway); gh pr checks 7 reads them"), "\(run.output)")
        #expect(run.output.contains("release: waiting for #7 to merge (OPEN BLOCKED, checks unread; gh pr checks 7 lists them)"), "\(run.output)")
    }

    /// A pull request no check has reported on yet has no checks pending, as gh says: that's no unread poll.
    @Test func noChecksReportedYetIsNoUnreadPoll() async throws {
        try await origin()
        try "OPEN BLOCKED\nOPEN BLOCKED\nMERGED CLEAN\n".write(to: state.appending(path: "states"), atomically: true, encoding: .utf8)
        try "release-0.2.0\n".write(to: state.appending(path: "merges"), atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: state.appending(path: "no-checks").path, contents: nil)
        let run = try await release()
        #expect(run.status == 0, "\(run.output)")
        #expect(!run.output.contains("couldn't read #7's checks"), "\(run.output)")
        #expect(run.output.contains("release: waiting for #7 to merge (OPEN BLOCKED, no checks reported yet; gh pr checks 7 lists them)"), "\(run.output)")
    }

    /// Whether auto-merge is on, and bringing a pull request up to date, are said when they fail, with the command for
    /// each.
    @Test func anAutoMergeReadOrAnUpdateThatFailsIsSaid() async throws {
        try await origin()
        try "OPEN BEHIND\nOPEN BLOCKED\nMERGED CLEAN\n".write(to: state.appending(path: "states"), atomically: true, encoding: .utf8)
        try "release-0.2.0\n".write(to: state.appending(path: "merges"), atomically: true, encoding: .utf8)
        for name in ["auto-fails", "update-fails"] { FileManager.default.createFile(atPath: state.appending(path: name).path, contents: nil) }
        let run = try await release()
        #expect(run.status == 0, "\(run.output)")
        #expect(run.output.contains("release: couldn't bring #7 up to date with main (HTTP 502: Bad Gateway); gh pr update-branch 7 does it"), "\(run.output)")
        #expect(run.output.contains("release: couldn't read whether auto-merge is on for #7 (HTTP 502: Bad Gateway); gh pr view 7 --json autoMergeRequest reads it"), "\(run.output)")
    }

    /// A poll that can't be read is said each time, with why and the command that reads it.
    @Test func aPollThatCantBeReadIsSaid() async throws {
        try await origin()
        try "MERGED CLEAN\n".write(to: state.appending(path: "state"), atomically: true, encoding: .utf8)
        try "release-0.2.0\n".write(to: state.appending(path: "merges"), atomically: true, encoding: .utf8)
        try "HTTP 502: Bad Gateway\n".write(to: state.appending(path: "view-fails"), atomically: true, encoding: .utf8)
        let run = try await release()
        #expect(run.status == 0, "\(run.output)")
        #expect(run.output.contains("release: couldn't read #7's state (HTTP 502: Bad Gateway); gh pr view 7 reads it"), "\(run.output)")
    }
}
