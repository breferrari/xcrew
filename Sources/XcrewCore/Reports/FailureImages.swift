import Foundation

/// A failed test's images, kept where Claude can Read them: the paths, in the order the notes list them, and their folder.
public struct FailureImages: Sendable, Equatable {
    public let paths: [String]
    public let folder: String

    /// Images listed for a test; the rest are counted, with their folder.
    static let mostShown = 3

    /// The images listed by path.
    var shown: [String] { Array(paths.prefix(Self.mostShown)) }

    /// `and 2 more images in <folder>`, for the images past those listed; nil when there are none.
    var more: String? {
        let count = paths.count - Self.mostShown
        guard count > 0 else { return nil }
        return "and \(count) more \(count == 1 ? "image" : "images") in \(folder)"
    }

    /// How long a run's images are kept: as long as the shim keeps a build no checkout has run.
    static let keptDays = 14

    /// A test's images among its exported attachments, moved to `<run>/<suite>/<test>/`: each snapshot comparison's
    /// reference, failing render and difference together, a repeated run's one comparison after another, the rest in the
    /// order they were attached. Nil when it attached none.
    static func keep(of test: TestID, from export: URL, in run: URL) -> FailureImages? {
        let found = attachments(of: test, in: export).compactMap { attachment -> (name: String, file: URL)? in
            guard let exported = attachment["exportedFileName"] as? String, let suggested = attachment["suggestedHumanReadableName"] as? String else { return nil }
            let file = export.appending(path: exported)
            return keptName(suggested: suggested, content: file).map { ($0, file) }
        }
        // The nth reference, failure and difference go together: one comparison's, in a run repeated with -test-iterations.
        var seen: [Int: Int] = [:]
        let images = found.enumerated().map { index, image in
            let rank = rank(image.name)
            defer { seen[rank, default: 0] += 1 }
            return (name: image.name, file: image.file, order: [seen[rank, default: 0], rank, index])
        }.sorted { $0.order.lexicographicallyPrecedes($1.order) }
        guard !images.isEmpty else { return nil }
        let folder = folder(of: test, in: run)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let kept = images.compactMap { image -> String? in
            let destination = folder.appending(path: image.name)
            return (try? FileManager.default.moveItem(at: image.file, to: destination)) != nil ? destination.path : nil
        }
        return kept.isEmpty ? nil : FailureImages(paths: kept, folder: folder.path)
    }

    /// A test's attachments as an export's `manifest.json` lists them.
    static func attachments(of test: TestID, in export: URL) -> [[String: Any]] {
        let manifest = (try? JSONSerialization.jsonObject(with: Data(contentsOf: export.appending(path: "manifest.json")))) as? [[String: Any]] ?? []
        return manifest.filter { ($0["testIdentifier"] as? String).map(TestID.init(xcresultID:)) == test }.flatMap { $0["attachments"] as? [[String: Any]] ?? [] }
    }

    /// Where a test's kept files go in a run's folder: `<run>/<suite>/<test>/`.
    static func folder(of test: TestID, in run: URL) -> URL {
        [test.suite, test.name].reduce(run) { $0.appending(path: $1.replacingOccurrences(of: "/", with: "-")) }
    }

    /// The first bytes of a file, or nil when it can't be read.
    static func head(of file: URL, bytes: Int) -> Data? {
        (try? FileHandle(forReadingFrom: file)).flatMap { handle in
            defer { try? handle.close() }
            return try? handle.read(upToCount: bytes)
        }
    }

    /// How much the kept images may take: a UI suite's snapshots run to megabytes a failure.
    static let keptBytes = 200 * 1024 * 1024

    /// The file in a run's folder that records the bytes its images take, written as they're kept.
    static let sizeRecord = ".size"

    /// Removes each run's images kept longer than `keptDays`, then the oldest runs' while all of them take more than
    /// `limit`; the newest run's stay whatever their size. Each run's size is read from its record, so pruning costs the
    /// same however many runs are kept; a run kept before sizes were recorded is measured once and recorded.
    static func prune(in folder: URL, keepingAtMost limit: Int = keptBytes, now: Date) {
        let kept = AgedEntries.removing(olderThan: Double(keptDays) * 24 * 3600, in: folder, now: now).map { (run: $0, bytes: recordedSize(of: $0)) }
        var total = kept.reduce(0) { $0 + $1.bytes }
        for (run, bytes) in kept.dropLast() where total > limit {
            try? FileManager.default.removeItem(at: run)
            total -= bytes
        }
    }

    /// A run's size as its record says, or measured and recorded when it has none.
    static func recordedSize(of run: URL) -> Int {
        (try? String(contentsOf: run.appending(path: sizeRecord), encoding: .utf8)).flatMap { Int($0) } ?? record(run)
    }

    /// Measures the bytes a run's kept files take, its record left out, and records them; the bytes. Its folder's date is
    /// put back as it was, since the date is the run's age. Each writer to a run calls it once its writes are done, never
    /// two at once on one run, as a measure taken before another's write would record too few.
    @discardableResult
    public static func record(_ run: URL) -> Int {
        guard let written = (try? run.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return 0 }
        let files = FileManager.default.enumerator(at: run, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL] ?? []
        let bytes = files.filter { $0.lastPathComponent != sizeRecord }.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
        try? Data(String(bytes).utf8).write(to: run.appending(path: sizeRecord), options: .atomic)
        try? FileManager.default.setAttributes([.modificationDate: written], ofItemAtPath: run.path)
        return bytes
    }

    /// Image formats Claude's Read shows, by extension: those Claude takes as images.
    static let extensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp"]

    /// The format a file's first bytes say it is, as its extension; nil when they say none of `extensions`.
    static func format(of data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        func starts(_ prefix: [UInt8], at offset: Int = 0) -> Bool {
            bytes.count >= offset + prefix.count && Array(bytes[offset..<offset + prefix.count]) == prefix
        }
        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "png" }
        if starts([0xFF, 0xD8, 0xFF]) { return "jpg" }
        if starts(Array("GIF8".utf8)) { return "gif" }
        if starts(Array("RIFF".utf8)), starts(Array("WEBP".utf8), at: 8) { return "webp" }
        return nil
    }

    /// The name an attachment is kept under when it's an image: its suggested name, with the extension its content says
    /// when the name has none of an image's. Nil when neither its name nor its content says image. The exported file's
    /// own extension says nothing: xcresulttool leaves some images without one.
    static func keptName(suggested: String, content: URL) -> String? {
        let name = suggested.replacingOccurrences(of: "/", with: "-")
        if extensions.contains(URL(fileURLWithPath: name).pathExtension.lowercased()) { return name }
        return head(of: content, bytes: 12).flatMap(format(of:)).map { "\(name).\($0)" }
    }

    /// Where an image sorts: a snapshot's reference, then its failing render, then their difference, by the words both
    /// libraries begin their names with (`reference`, `Reference Image`; `failure`, `Failed Image`; `difference`,
    /// `Diffed Image`), then the rest.
    static func rank(_ name: String) -> Int {
        let lowered = name.lowercased()
        return ["ref", "fail", "diff"].firstIndex { lowered.hasPrefix($0) } ?? 3
    }
}
