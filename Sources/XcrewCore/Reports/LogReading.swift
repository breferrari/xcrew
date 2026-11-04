import Foundation

/// What a run's log has said so far, kept between readings so each reads on from where the last stopped: a clean
/// build's log runs to tens of megabytes, and the band asks once a second. Read in pieces, it comes to what reading the
/// whole log at once does.
struct LogReading: Codable, Equatable, Sendable {
    /// Where testing starts: xcodebuild's own first `Test Suite '…'` line for XCTest, or Swift Testing's
    /// `◇ Test run started.`, whichever comes first. MobileBuildMCP writes its `Testing started` only once the tests have
    /// run, so the last of those is the last resort (docs/findings.md, *Test progress in a run's log*).
    enum Start: String, Codable, Sendable {
        case none, testingStarted, tests
    }

    /// The file read, by its number on its volume: another file at the log's path is another log.
    var file: Int?
    /// The bytes read: up to the end of the last whole line.
    var offset: UInt64 = 0
    var start = Start.none
    /// The tests finished since the start of testing.
    var progress = TestProgress()
    var testBuildSucceeded = false
    /// The latest task's step, as `RunLog.buildStep` reads it.
    var step: String?
    /// The line still being written at the end: counted in this reading's phase, read again whole by the next.
    var pending: String?
    /// The scheme the log's first invocation names, read wherever the log has it, as `RunLog.scheme(in:)` reads it.
    var scheme: String?
    /// The invocation's heading was the last line read, so the next is the invocation itself.
    var awaitsInvocation = false
    /// The first invocation was read: a later one is another xcodebuild's, as one a build's script started.
    var invocationRead = false
    /// The latest `** … **` verdict xcodebuild wrote.
    var verdict: String?

    /// Removes the readings kept in `folder` that no one has kept for a day before `now`: a run's log is followed only while
    /// it runs.
    static func prune(in folder: URL, now: Date) {
        AgedEntries.removing(olderThan: 24 * 3600, in: folder, now: now)
    }

    /// Reads the log at `url` on from `kept`; afresh when `kept` read another file, or more than the log now holds.
    static func reading(_ url: URL, after kept: LogReading?) -> LogReading? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let file = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.systemFileNumber] as? Int
        var reading = kept.flatMap { $0.offset <= size && $0.file == file ? $0 : nil } ?? LogReading(file: file)
        guard (try? handle.seek(toOffset: reading.offset)) != nil, let appended = try? handle.readToEnd() ?? Data() else { return nil }
        reading.read(appended)
        return reading
    }

    /// Reads the whole lines `appended` holds, and keeps the one still being written. Until testing starts only a line
    /// whose first byte may begin one that counts is read, and the step only from the latest task: a build's log is
    /// mostly lines that say neither.
    mutating func read(_ appended: Data) {
        let newline = UInt8(ascii: "\n")
        let whole = appended.lastIndex(of: newline).map { $0 + 1 } ?? appended.startIndex
        var isFirst = offset == 0
        for line in appended[..<whole].dropLast().split(separator: newline, omittingEmptySubsequences: false) where whole > appended.startIndex {
            if !invocationRead {
                let text = String(decoding: line, as: UTF8.self)
                if awaitsInvocation {
                    scheme = RunLog.scheme(inInvocation: text)
                    invocationRead = true
                }
                awaitsInvocation = !awaitsInvocation && text.hasPrefix("Command line invocation:")
            }
            if let found = Self.verdict(in: line) { verdict = found }
            if line.isEmpty { isFirst = false; continue }
            if start != .none || line.first.map(Self.mayBegin) == true {
                read(line: String(decoding: line, as: UTF8.self)[...], isFirst: isFirst)
            }
            isFirst = false
        }
        if let found = Self.lastStep(in: appended[..<whole]) { step = found }
        offset += UInt64(whole - appended.startIndex)
        pending = whole < appended.endIndex ? String(decoding: appended[whole...], as: UTF8.self) : nil
        if let pending, let found = Self.verdict(in: Data(pending.utf8)[...]) { verdict = found }
    }

    /// A `** … **` verdict, as xcodebuild writes one, its line trimmed; nil for any other line.
    static func verdict(in line: Data.SubSequence) -> String? {
        guard line.contains(UInt8(ascii: "*")) else { return nil }
        let text = String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return text.hasPrefix("** ") && text.hasSuffix(" **") ? text : nil
    }

    /// The first bytes of the lines read before testing starts: `Test Suite '`, `Testing started`, `◇ Test run started.`
    /// and `** TEST BUILD SUCCEEDED **`.
    static func mayBegin(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "T") || byte == UInt8(ascii: "*") || byte == Array("◇".utf8)[0]
    }

    /// The latest task's step in `lines`: each `(in target '` from the end is found in the bytes and only its own line
    /// is read.
    static func lastStep(in lines: Data) -> String? {
        let mark = Data("(in target '".utf8), newline = UInt8(ascii: "\n")
        var searchEnd = lines.endIndex
        while let found = lines.range(of: mark, options: .backwards, in: lines.startIndex..<searchEnd) {
            let start = lines[..<found.lowerBound].lastIndex(of: newline).map { $0 + 1 } ?? lines.startIndex
            let end = lines[found.upperBound...].firstIndex(of: newline) ?? lines.endIndex
            if let step = RunLog.buildStep(String(decoding: lines[start..<end], as: UTF8.self)) { return step }
            searchEnd = start
        }
        return nil
    }

    /// One line, but for its step. `** TEST BUILD SUCCEEDED **` counts only after another line.
    mutating func read(line: Substring, isFirst: Bool) {
        if line.hasPrefix("Test Suite '") || line.hasPrefix("◇ Test run started.") {
            if start != .tests { (start, progress) = (.tests, TestProgress()) }
        } else if line.hasPrefix("Testing started"), start != .tests {
            (start, progress) = (.testingStarted, TestProgress())
        }
        if start != .none { progress.read(line) }
        if !isFirst, line.hasPrefix("** TEST BUILD SUCCEEDED **") { testBuildSucceeded = true }
    }

    /// The phase the log has reached, its line still being written included.
    func phase(expectedTests: Int?) -> String? {
        var reading = self
        if let pending, !pending.isEmpty {
            reading.read(line: pending[...], isFirst: offset == 0)
            if pending.contains("(in target '"), let found = RunLog.buildStep(pending) { reading.step = found }
        }
        if reading.start != .none {
            let done = reading.progress.finished
            if reading.progress.isRepeated { return "testing" }
            if let expectedTests, done <= expectedTests { return "testing \(done) of \(expectedTests)" }
            return "testing · \(done) done"
        }
        return reading.testBuildSucceeded ? "testing" : reading.step
    }
}
