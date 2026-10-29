import Foundation
import Testing

/// Runs the real `bin/xcrew` against a copy of the repository's layout, with a fake `swift` that
/// records each build and produces a stand-in binary.
@Suite struct ShimTests {
    let root: URL
    let cache: URL
    let log: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "xcrew-shim-\(UUID().uuidString)")
        root = base.appending(path: "plugin")
        cache = base.appending(path: "cache")
        log = base.appending(path: "builds.log")
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try FileManager.default.createDirectory(at: root.appending(path: "bin"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: repository.appending(path: "bin/xcrew"), to: root.appending(path: "bin/xcrew"))
        try write("// swift-tools-version:6.0\n", to: "Package.swift")
        try write("print(1)\n", to: "Sources/xcrew/main.swift")

        // The fake swift writes a binary that prints its arguments and XCREW_ROOT.
        let fakeSwift = """
        #!/bin/sh
        echo build >> "\(log.path)"
        [ -n "${BUILD_SECONDS:-}" ] && sleep "$BUILD_SECONDS"
        [ -n "${FAIL_BUILD:-}" ] && { echo "compile error" >&2; exit 1; }
        while [ $# -gt 0 ]; do [ "$1" = --scratch-path ] && scratch="$2"; shift; done
        mkdir -p "$scratch/release"
        printf '#!/bin/sh\\necho "ran $* root=$XCREW_ROOT"\\n' > "$scratch/release/xcrew"
        chmod +x "$scratch/release/xcrew"
        """
        try write(fakeSwift, to: "fakebin/swift", executable: true)
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
    func physicalPath(_ url: URL) async throws -> String {
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

    var builds: Int {
        ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").count
    }

    @Test func buildsOnFirstUseAndRunsTheBinary() async throws {
        let run = try await shim("doctor", "--list")
        #expect(run.status == 0)
        #expect(run.output == "ran doctor --list root=\(try await physicalPath(root))\n")
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
        let first = try FileManager.default.contentsOfDirectory(atPath: cache.path).filter { $0 != "build" }
        let stale = cache.appending(path: "0000000000000000")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -15 * 86_400)], ofItemAtPath: stale.path)
        try write("print(3)\n", to: "Sources/xcrew/main.swift")
        _ = try await shim("help")
        let second = Set(try FileManager.default.contentsOfDirectory(atPath: cache.path).filter { $0 != "build" })
        #expect(first.count == 1)
        #expect(second.count == 2)
        #expect(second.isSuperset(of: first))
        #expect(!second.contains(stale.lastPathComponent))
    }
}

extension ShimTests {
    /// At session start the session hook and the mod both start the shim; after an update only one may build.
    @Test func twoFirstRunsAtOnceBuildOnce() async throws {
        async let first = shim("help", environment: ["BUILD_SECONDS": "1"])
        async let second = shim("help", environment: ["BUILD_SECONDS": "1"])
        let runs = try await [first, second]
        #expect(runs.allSatisfy { $0.status == 0 && $0.output.hasPrefix("ran help") })
        #expect(builds == 1)
    }
}
