import Foundation

/// A folder's entries by when each was last modified, for removing those kept too long: the session stamps, the log
/// readings and the failed tests' images each prune their folder through it.
enum AgedEntries {
    /// Removes the entries of `folder` last modified more than `age` seconds before `now`, and answers the rest with
    /// their dates, oldest first. An entry whose date can't be read counts as modified `now`.
    @discardableResult
    static func removing(olderThan age: TimeInterval, in folder: URL, now: Date) -> [(url: URL, modified: Date)] {
        let oldest = now.addingTimeInterval(-age)
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let dated = entries.map { (url: $0, modified: (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now) }
        for entry in dated where entry.modified < oldest { try? FileManager.default.removeItem(at: entry.url) }
        return dated.filter { $0.modified >= oldest }.sorted { $0.modified < $1.modified }
    }
}
