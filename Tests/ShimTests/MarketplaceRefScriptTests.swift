import Foundation
import Testing

/// Runs the real `scripts/marketplace-ref.sh`, which compares the commit installs follow (`stable`) with the latest
/// release's.
@Suite struct MarketplaceRefScriptTests {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// 2026-10-29T18:00:00Z.
    let released: Int = 1_793_296_800
    static let tagged = String(repeating: "a", count: 40)
    static let older = String(repeating: "b", count: 40)

    func check(stable: String, hoursLater: Int) async throws -> (status: Int32, errors: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [repository.appending(path: "scripts/marketplace-ref.sh").path, "v0.8.3", "2026-10-29T18:00:00Z", String(released + hoursLater * 3600), stable, Self.tagged]
        process.standardInput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try await ShimTests.runToEnd(process)
        return (process.terminationStatus, String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    @Test func stableOnTheLatestReleasePasses() async throws {
        #expect(try await check(stable: Self.tagged, hoursLater: 48).status == 0)
    }

    /// The release workflow moves `stable` as its last step; a day covers a run that's still going many times over.
    @Test func stableBehindForADayFailsNamingTheFix() async throws {
        #expect(try await check(stable: Self.older, hoursLater: 2).status == 0)
        let late = try await check(stable: Self.older, hoursLater: 25)
        #expect(late.status == 1)
        #expect(late.errors == "installs follow stable at bbbbbbbbbbbb, but v0.8.3 (aaaaaaaaaaaa) was released at 2026-10-29T18:00:00Z: rerun its release workflow, or push it with git push origin aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:refs/heads/stable\n")
    }
}
