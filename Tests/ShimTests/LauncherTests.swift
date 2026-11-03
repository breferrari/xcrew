import Foundation
import Testing
import XcrewTestSupport

/// The MobileBuildMCP launcher with a project that pins its Xcode: it asks the xcrew CLI for the pinned developer folder,
/// waiting for its answer however long it takes and never building it, and records what it did for the doctor.
@Suite struct LauncherTests {
    let base = FileManager.default.temporaryDirectory.appending(path: "xcrew-launcher-\(UUID().uuidString)")
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    var plugin: URL { base.appending(path: "plugin") }
    var project: URL { base.appending(path: "project") }
    var cache: URL { base.appending(path: "cache") }

    init() throws {
        try FileManager.default.createDirectory(at: plugin.appending(path: "libexec"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: repository.appending(path: "libexec/mobilebuildmcp-server"), to: plugin.appending(path: "libexec/mobilebuildmcp-server"))
        try write("#!/bin/sh\necho \"cwd=$(pwd -P) developer=${DEVELOPER_DIR:-none}\"\n", to: base.appending(path: "fakemcp/mobilebuildmcp"))
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// The xcrew CLI as the launcher finds it, answering `xcode --developer-dir` with `script`.
    func xcrew(_ script: String) throws {
        try write("#!/bin/sh\n[ \"$*\" = \"--if-built xcode --developer-dir\" ] || exit 9\n\(script)\n", to: plugin.appending(path: "bin/xcrew"))
    }

    func pin() throws {
        try "26.4\n".write(to: project.appending(path: ".xcode-version"), atomically: true, encoding: .utf8)
    }

    /// What the fake server printed, and what the launcher printed to standard error, which Claude Code logs for a server.
    func start(in folder: URL? = nil) async throws -> (output: String, errors: String) {
        let process = Process()
        process.executableURL = plugin.appending(path: "libexec/mobilebuildmcp-server")
        process.arguments = [(folder ?? project).path]
        process.environment = ["PATH": "\(base.appending(path: "fakemcp").path):/usr/bin:/bin", "HOME": base.path, "XCREW_CACHE": cache.path]
        process.standardInput = FileHandle.nullDevice
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try await ShimTests.runToEnd(process)
        let read = { (pipe: Pipe) in String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) }
        return (read(output), read(errors))
    }

    /// The project's real path, as the launcher's `pwd -P` prints it.
    func real() async throws -> String {
        try await ShimTests.physicalPath(project)
    }

    /// The launcher's record for the project: below `launches`, at its real path, with a suffix, so a project inside
    /// another has a record of its own beside the folder of the other's.
    func recordPath(of folder: URL? = nil) async throws -> String {
        cache.path + "/launches" + (try await ShimTests.physicalPath(folder ?? project)) + ".launch"
    }

    func record() async throws -> String? {
        try? String(contentsOfFile: try await recordPath(), encoding: .utf8)
    }

    @Test func aPinnedXcodeTheCLINamesIsTheServersDeveloperFolder() async throws {
        try pin()
        try xcrew("echo /Apps/Xcode-26.4.app/Contents/Developer")
        let started = try await start()
        #expect(started.output == "cwd=\(try await real()) developer=/Apps/Xcode-26.4.app/Contents/Developer\n")
        #expect(try await record() == "applied /Apps/Xcode-26.4.app/Contents/Developer\n")
        #expect(started.errors == "")
    }

    /// The CLI's first build takes seconds: the launcher never starts one, and says so.
    @Test func aCLINotYetBuiltLeavesTheServerAsWithoutAPinAndSaysWhy() async throws {
        try pin()
        try xcrew("exit 75")
        #expect(try await start().output == "cwd=\(try await real()) developer=none\n")
        #expect(try await record() == "not built\n")
    }

    /// The launcher waits for the pin's answer however long it takes: here the CLI answers only once the test lets it, and
    /// any `sleep` returns at once, so a timer of the launcher's own would have stopped it first.
    @Test func thePinIsAppliedHoweverLongItsReadTakes() async throws {
        try pin()
        let started = base.appending(path: "started"), release = base.appending(path: "release")
        try write("#!/bin/sh\nexit 0\n", to: base.appending(path: "fakemcp/sleep"))
        try xcrew("touch \"\(started.path)\"; while [ ! -e \"\(release.path)\" ]; do /bin/sleep 0.01; done; echo /Apps/Xcode-26.4.app/Contents/Developer")
        let launcher = Task { try await start() }
        try await until { FileManager.default.fileExists(atPath: started.path) }
        FileManager.default.createFile(atPath: release.path, contents: nil)
        #expect(try await launcher.value.output == "cwd=\(try await real()) developer=/Apps/Xcode-26.4.app/Contents/Developer\n")
        #expect(try await record() == "applied /Apps/Xcode-26.4.app/Contents/Developer\n")
    }

    @Test func aPinNoInstalledXcodeMatchesIsRecorded() async throws {
        try pin()
        try xcrew("exit 4")
        #expect(try await start().output == "cwd=\(try await real()) developer=none\n")
        #expect(try await record() == "no match\n")
    }

    /// Without a pin the CLI isn't asked, and an earlier start's record goes: the server no longer has its Xcode.
    @Test func withoutAPinTheCLIIsNotAskedAndTheOldRecordGoes() async throws {
        try xcrew("echo asked >> \"\(base.path)/asked\"; exit 3")
        let path = try await recordPath()
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        try "applied /Apps/Xcode-26.4.app/Contents/Developer\n".write(toFile: path, atomically: true, encoding: .utf8)
        #expect(try await start().output == "cwd=\(try await real()) developer=none\n")
        #expect(!FileManager.default.fileExists(atPath: base.appending(path: "asked").path))
        #expect(try await record() == nil)
    }

    /// A CLI that fails isn't one that took too long: the doctor names what happened.
    @Test func aCLIThatFailsIsRecordedAsFailing() async throws {
        try pin()
        try xcrew("exit 1")
        #expect(try await start().output == "cwd=\(try await real()) developer=none\n")
        #expect(try await record() == "failed 1\n")
    }

    /// A project inside another, each started in its turn, keeps a record of its own.
    @Test func aProjectInsideAnotherHasItsOwnRecord() async throws {
        try pin()
        try xcrew("echo /Apps/Xcode-26.4.app/Contents/Developer")
        _ = try await start()
        let inner = project.appending(path: "ios")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try "26.4\n".write(to: inner.appending(path: ".xcode-version"), atomically: true, encoding: .utf8)
        _ = try await start(in: inner)
        #expect(try String(contentsOfFile: try await recordPath(of: inner), encoding: .utf8) == "applied /Apps/Xcode-26.4.app/Contents/Developer\n")
        #expect(try await record() == "applied /Apps/Xcode-26.4.app/Contents/Developer\n")
    }

    /// A pin inside a dependency or a hidden folder is a vendored project's, not this one's: the CLI isn't asked.
    @Test func aVendoredProjectsPinIsNotThisOnes() async throws {
        try xcrew("echo asked >> \"\(base.path)/asked\"; exit 3")
        for folder in ["Pods/Charts", "node_modules/kit", ".build/checkouts"] {
            try FileManager.default.createDirectory(at: project.appending(path: folder), withIntermediateDirectories: true)
            try "16.0\n".write(to: project.appending(path: "\(folder)/.xcode-version"), atomically: true, encoding: .utf8)
        }
        #expect(try await start().output == "cwd=\(try await real()) developer=none\n")
        #expect(!FileManager.default.fileExists(atPath: base.appending(path: "asked").path))
    }
}
