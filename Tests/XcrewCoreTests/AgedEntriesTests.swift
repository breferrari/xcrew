import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// A folder's entries kept too long go, the rest stay: what the session stamps, the log readings and the failed tests'
/// images each prune.
@Suite struct AgedEntriesTests {
    @Test func entriesOlderThanTheAgeGoAndTheRestAreReturned() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "xcrew-aged-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        for (name, age) in [("old", 3 * 86_400.0), ("new", 3_600.0)] {
            let file = folder.appending(path: name)
            try Data().write(to: file)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: file.path)
        }
        let kept = AgedEntries.removing(olderThan: 2 * 86_400, in: folder, now: now)
        #expect(kept.map(\.lastPathComponent) == ["new"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["new"])
    }
}
