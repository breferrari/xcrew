import Foundation
import Testing
import XcrewTestSupport

/// Runs the real `bin/xcrew` against a copy of the repository's layout, with a fake `swift` that
/// records each build and produces a stand-in binary.
@Suite struct ShimTests {
    let root: URL
    let cache: URL
    let log: URL
    let hashLog: URL
    /// Each `sleep` the shim makes, by a stand-in on the PATH that logs it and then sleeps.
    let sleepLog: URL
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    init() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "xcrew-shim-\(UUID().uuidString)")
        root = base.appending(path: "plugin")
        cache = base.appending(path: "cache")
        log = base.appending(path: "builds.log")
        hashLog = base.appending(path: "hashes.log")
        sleepLog = base.appending(path: "sleeps.log")
        try FileManager.default.createDirectory(at: root.appending(path: "bin"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: repository.appending(path: "bin/xcrew"), to: root.appending(path: "bin/xcrew"))
        try write("// swift-tools-version:6.0\n", to: "Package.swift")
        try write("print(1)\n", to: "Sources/xcrew/main.swift")

        // The fake swift writes a binary that prints its arguments and XCREW_ROOT.
        let fakeSwift = """
        #!/bin/sh
        echo build >> "\(log.path)"
        [ -n "${BUILD_SECONDS:-}" ] && sleep "$BUILD_SECONDS"
        # Held until the test writes a line to this FIFO: the build is still going when the test says.
        [ -n "${HOLD_BUILD:-}" ] && read -r _ < "$HOLD_BUILD"
        [ -n "${FAIL_BUILD:-}" ] && { echo "compile error" >&2; exit 1; }
        while [ $# -gt 0 ]; do [ "$1" = --scratch-path ] && scratch="$2"; shift; done
        mkdir -p "$scratch/release"
        printf '#!/bin/sh\\necho "ran $* root=$XCREW_ROOT"\\n' > "$scratch/release/xcrew"
        chmod +x "$scratch/release/xcrew"
        """
        try write(fakeSwift, to: "fakebin/swift", executable: true)
        // Logs each wait, so a test asserts how often the shim waited rather than how long it took.
        try write("#!/bin/sh\necho \"$*\" >> \"\(sleepLog.path)\"\nexec /bin/sleep \"$@\"\n", to: "fakebin/sleep", executable: true)
        // Counts the hashing of the sources, the cost a second run should skip.
        try write("""
        #!/bin/sh
        echo hash >> "\(hashLog.path)"
        # Stands for an edit saved while the sources are being hashed.
        # Its time is set a second on, as an edit saved after hashing began would have it, rather than waited for.
        if [ -n "${EDIT_DURING_HASH:-}" ]; then edited="\(root.appending(path: "Sources/xcrew/main.swift").path)"; echo "// edited" >> "$edited"; touch -A 01 "$edited"; fi
        exec /usr/bin/shasum "$@"
        """, to: "fakebin/shasum", executable: true)
    }

    func write(_ text: String, to path: String, executable: Bool = false) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
    }

    func shim(_ arguments: String..., environment: [String: String] = [:]) async throws -> (status: Int32, output: String, errors: String) {
        let process = Process()
        process.executableURL = root.appending(path: "bin/xcrew")
        process.arguments = arguments
        process.environment = [
            "PATH": "\(root.appending(path: "fakebin").path):/usr/bin:/bin",
            "HOME": FileManager.default.temporaryDirectory.path,
            "XCREW_CACHE": cache.path,
        ].merging(environment) { $1 }
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try await Self.runToEnd(process)
        let read = { (pipe: Pipe) in String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) }
        return (process.terminationStatus, read(output), read(errors))
    }

    /// The path with every symlink resolved, as `pwd -P` prints it (Foundation drops `/private`).
    static func physicalPath(_ url: URL) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/pwd")
        process.arguments = ["-P"]
        process.currentDirectoryURL = url
        let output = Pipe()
        process.standardOutput = output
        try await Self.runToEnd(process)
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .newlines)
    }

    /// Awaits a process instead of blocking a thread with `waitUntilExit`: every suite shares one
    /// test process, and a blocked thread pool starves the tests that measure time.
    static func runToEnd(_ process: Process) async throws {
        let exit = AsyncStream<Void> { continuation in
            process.terminationHandler = { _ in continuation.finish() }
        }
        try process.run()
        for await _ in exit {}
    }

    /// What a fake `program` printed when `executable` started it: a server script, or the inline command it replaced.
    func startServer(_ executable: String, _ arguments: [String], faking program: String, as fake: String) async throws -> String {
        try write("#!/bin/sh\n\(fake)\n", to: "fakemcp/\(program)", executable: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "\(root.appending(path: "fakemcp").path):/usr/bin:/bin"]
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        try await Self.runToEnd(process)
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    /// The plugin's server script starts MobileBuildMCP exactly as the `sh -c` line in `.mcp.json` did.
    @Test func theServerScriptStartsMobileBuildMCPAsTheInlineCommandDid() async throws {
        let project = root.appending(path: "project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let inline = #"cd "$1" && PATH="$PATH:/opt/homebrew/bin:/usr/local/bin" exec mobilebuildmcp mcp"#
        let fake = #"echo "cwd=$(pwd -P) args=$* path=$PATH""#
        let before = try await startServer("/bin/sh", ["-c", inline, "mobilebuildmcp", project.path], faking: "mobilebuildmcp", as: fake)
        let after = try await startServer(repository.appending(path: "libexec/mobilebuildmcp-server").path, [project.path], faking: "mobilebuildmcp", as: fake)
        #expect(before.contains("cwd=\(try await Self.physicalPath(project)) args=mcp path="))
        #expect(before.hasSuffix(":/opt/homebrew/bin:/usr/local/bin\n"))
        #expect(after == before)
    }

    /// The plugin's Xcode MCP script starts `xcrun mcpbridge`, as the server's inline command did.
    @Test func theXcodeServerScriptStartsTheBridgeAsTheManifestDid() async throws {
        let started = try await startServer(repository.appending(path: "libexec/xcode-mcp-server").path, [], faking: "xcrun", as: #"echo "args=$*""#)
        #expect(started == "args=mcpbridge\n")
    }

    func lines(in file: URL) -> Int {
        ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").count
    }

    var builds: Int { lines(in: log) }

    @Test func buildsOnFirstUseAndRunsTheBinary() async throws {
        let run = try await shim("doctor", "--list")
        #expect(run.status == 0)
        #expect(run.output == "ran doctor --list root=\(try await Self.physicalPath(root))\n")
        #expect(builds == 1)
    }

    /// The MobileBuildMCP launcher asks only of a build that's there: `--if-built` never starts one.
    @Test func ifBuiltRunsABuildThatIsThereAndNeverBuilds() async throws {
        let before = try await shim("--if-built", "xcode")
        #expect(before.status == 75)
        #expect(builds == 0)
        _ = try await shim("help")
        let after = try await shim("--if-built", "xcode")
        #expect(after.output == "ran xcode root=\(try await Self.physicalPath(root))\n")
        #expect(builds == 1)
    }

    @Test func reusesTheBuild() async throws {
        _ = try await shim("help")
        _ = try await shim("help")
        #expect(builds == 1)
    }

    @Test func rebuildsWhenTheSourcesChange() async throws {
        _ = try await shim("help")
        try write("print(2)\n", to: "Sources/xcrew/main.swift")
        _ = try await shim("help")
        #expect(builds == 2)
    }

    @Test func aFailedBuildFailsLoudlyAndCachesNothing() async throws {
        let failed = try await shim("help", environment: ["FAIL_BUILD": "1"])
        #expect(failed.status != 0)
        #expect(failed.errors.contains("compile error"))
        _ = try await shim("help")
        #expect(builds == 2)
    }

    @Test func buildOutputStaysOffStandardOutput() async throws {
        // Hooks print JSON on stdout; anything else there breaks the reply.
        let run = try await shim("help")
        #expect(!run.output.contains("build"))
    }
}

extension ShimTests {
    /// Another checkout's build is kept while it's in use, so the installed plugin and a development
    /// clone don't rebuild in turn; one unused for two weeks goes.
    @Test func aRebuildKeepsRecentBuildsAndRemovesStaleOnes() async throws {
        _ = try await shim("help")
        let first = try FileManager.default.contentsOfDirectory(atPath: cache.path).filter { !["build", "roots"].contains($0) }
        let stale = cache.appending(path: "0000000000000000")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -15 * 86_400)], ofItemAtPath: stale.path)
        try write("print(3)\n", to: "Sources/xcrew/main.swift")
        _ = try await shim("help")
        let second = Set(try FileManager.default.contentsOfDirectory(atPath: cache.path).filter { !["build", "roots"].contains($0) })
        #expect(first.count == 1)
        #expect(second.count == 2)
        #expect(second.isSuperset(of: first))
        #expect(!second.contains(stale.lastPathComponent))
    }
}

extension ShimTests {
    /// At session start the session hook and the mod both start the shim; after an update only one may build.
    @Test func twoFirstRunsAtOnceBuildOnce() async throws {
        let hold = cache.deletingLastPathComponent().appending(path: "hold")
        let fifo = Process()
        fifo.executableURL = URL(fileURLWithPath: "/usr/bin/mkfifo")
        fifo.arguments = [hold.path]
        try await Self.runToEnd(fifo)
        // The first run's build is held; the second starts only once it is, and the build is let go only once the second
        // waits on the lock, so the two always overlap.
        async let first = shim("help", environment: ["HOLD_BUILD": hold.path])
        try await until { builds == 1 }
        let secondDone = Flag()
        let second = Task {
            let run = try await shim("help")
            secondDone.set()
            return run
        }
        // The second waits on the lock, or, with no lock, builds and finishes: either ends the wait, and the build is let go.
        try await until { lines(in: sleepLog) > 0 || secondDone.isSet }
        let writer = try FileHandle(forWritingTo: hold)
        try writer.write(contentsOf: Data("go\n".utf8))
        try writer.close()
        let runs = try await [first, second.value]
        #expect(lines(in: sleepLog) > 0, "the second run didn't wait on the first's build")
        #expect(runs.allSatisfy { $0.status == 0 && $0.output.hasPrefix("ran help") })
        #expect(builds == 1)
    }

    /// Waits for `condition`, which another process makes true, checking it often; a hang guard ends the wait.
    func until(_ condition: () -> Bool) async throws {
        for _ in 0..<50_000 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition(), "never came true")
    }
}

extension ShimTests {
    /// A build killed outright (SIGKILL runs no trap) leaves its lock behind; the next run clears it
    /// at once rather than waiting out the ten-minute backstop.
    @Test func aLockLeftByAKilledBuildIsCleared() async throws {
        let lock = cache.appending(path: ".lock")
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: true)
        try "999999".write(to: lock.appending(path: "pid"), atomically: true, encoding: .utf8)
        let run = try await shim("help")
        #expect(run.status == 0 && run.output.hasPrefix("ran help"))
        // Cleared at once: the shim never waited on the lock.
        #expect(lines(in: sleepLog) == 0)
        #expect(!FileManager.default.fileExists(atPath: lock.path))
    }
}

extension ShimTests {
    var hashes: Int { lines(in: hashLog) }

    /// The band asks once a second while a build runs; the key is worked out once, not on every call.
    @Test func laterRunsDontHashTheSourcesAgain() async throws {
        _ = try await shim("help")
        _ = try await shim("help")
        _ = try await shim("help")
        #expect(hashes == 1)
        #expect(builds == 1)
        // The key lives in the cache, not in the plugin folder, which may not be writable.
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".xcrew-key").path))
    }

    @Test func deletingASourceStillRebuilds() async throws {
        try write("print(4)\n", to: "Sources/xcrew/Extra.swift")
        _ = try await shim("help")
        try FileManager.default.removeItem(at: root.appending(path: "Sources/xcrew/Extra.swift"))
        _ = try await shim("help")
        #expect(builds == 2)
    }

    /// The mod asks for the build once per run, then runs it directly on its once-a-second path.
    @Test func itNamesTheBuildItWouldRun() async throws {
        let run = try await shim("--binary-path")
        #expect(run.status == 0)
        let path = run.output.trimmingCharacters(in: .newlines)
        #expect(path.hasPrefix(try await Self.physicalPath(cache)) || path.hasPrefix(cache.path))
        #expect(FileManager.default.isExecutableFile(atPath: path))
        #expect(builds == 1)
    }
}

extension ShimTests {
    /// Unpacking or `cp -p` sets a file's modification time back; its change time still says it's new.
    @Test func aSourceRestoredWithAnOldTimeStillRebuilds() async throws {
        _ = try await shim("help")
        let main = root.appending(path: "Sources/xcrew/main.swift")
        try "print(5)\n".write(to: main, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -86_400)], ofItemAtPath: main.path)
        _ = try await shim("help")
        #expect(builds == 2)
    }

    /// The key is stamped with the time hashing began, so an edit saved meanwhile is seen next time.
    @Test func anEditSavedWhileHashingIsSeenNextTime() async throws {
        _ = try await shim("help", environment: ["EDIT_DURING_HASH": "1"])
        _ = try await shim("help")
        #expect(builds == 2)
    }
}

extension ShimTests {
    /// An installed plugin builds once a version: its 200 MB scratch folder speeds no later build, so it goes. A
    /// development clone keeps its own for the next edit's build.
    @Test func aPluginInstallsBuildLeavesNoScratchFolder() async throws {
        _ = try await shim("help")
        #expect(!FileManager.default.fileExists(atPath: cache.appending(path: "build").path))
        #expect(builds == 1)
    }

    @Test func aGitCheckoutKeepsItsScratchFolder() async throws {
        try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
        _ = try await shim("help")
        #expect(FileManager.default.fileExists(atPath: cache.appending(path: "build/release/xcrew").path))
    }

    /// Each plugin version is a new checkout path with its own stamp: a stamp no build has written for two weeks goes at
    /// the next build, and this checkout's stays.
    @Test func aStampNoBuildHasWrittenForTwoWeeksGoes() async throws {
        let stale = cache.appending(path: "roots/plugins/cache/xcrew/0.8.1.key")
        try FileManager.default.createDirectory(at: stale.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "0000000000000000\n".write(to: stale, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -15 * 86_400)], ofItemAtPath: stale.path)
        _ = try await shim("help")
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        let current = cache.appending(path: "roots" + (try await Self.physicalPath(root)) + ".key")
        #expect(FileManager.default.fileExists(atPath: current.path))
    }
}
