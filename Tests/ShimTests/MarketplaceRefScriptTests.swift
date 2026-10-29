import Foundation
import Testing

/// Runs the real `scripts/marketplace-ref.sh` against a copy of `marketplace.json` naming `v0.8.2`.
@Suite struct MarketplaceRefScriptTests {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// 2026-10-29T18:00:00Z.
    let released: Int = 1_793_296_800

    func check(latest: String, hoursLater: Int) async throws -> (status: Int32, errors: String) {
        let root = FileManager.default.temporaryDirectory.appending(path: "xcrew-ref-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "scripts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: ".claude-plugin"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: repository.appending(path: "scripts/marketplace-ref.sh"), to: root.appending(path: "scripts/marketplace-ref.sh"))
        try #"{"plugins":[{"name":"xcrew","source":{"source":"github","repo":"breferrari/xcrew","ref":"v0.8.2"}}]}"#.write(to: root.appending(path: ".claude-plugin/marketplace.json"), atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [root.appending(path: "scripts/marketplace-ref.sh").path, latest, "2026-10-29T18:00:00Z", String(released + hoursLater * 3600)]
        process.standardInput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try await ShimTests.runToEnd(process)
        return (process.terminationStatus, String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    @Test func aRefOnTheLatestReleasePasses() async throws {
        #expect(try await check(latest: "v0.8.2", hoursLater: 48).status == 0)
    }

    /// The pull request that moves the ref runs after each release; a day covers its CI many times over.
    @Test func aRefBehindForADayFailsNamingBoth() async throws {
        #expect(try await check(latest: "v0.8.3", hoursLater: 2).status == 0)
        let late = try await check(latest: "v0.8.3", hoursLater: 25)
        #expect(late.status == 1)
        #expect(late.errors == "marketplace.json installs v0.8.2, but v0.8.3 was released at 2026-10-29T18:00:00Z: merge its 'chore: Install 0.8.3 from the marketplace' pull request, or run scripts/release.sh 0.8.3 to open it\n")
    }
}
