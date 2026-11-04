import Foundation
import Testing
@testable import XcrewCore

/// A report's states are written under the keys the mod reads (hooks/mod/cli.ts), each absent but for its own, and read
/// back as the same report.
struct ReportCodingTests {
    static func json(_ report: Report) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(report), as: UTF8.self)
    }

    @Test(arguments: [
        (Report.Reading.result, nil as Report.PinNote?, #"{"failures":[],"notes":[],"ok":false}"#),
        (.unread(task: nil), nil, #"{"failures":[],"isUnread":true,"notes":[],"ok":false}"#),
        (.unread(task: "k4q5tm9v2"), nil, #"{"backgroundTask":"k4q5tm9v2","failures":[],"isUnread":true,"notes":[],"ok":false}"#),
        (.verdictOnly, nil, #"{"failures":[],"isVerdictOnly":true,"notes":[],"ok":false}"#),
        (.result, .init(note: "xcrew: other Xcode", pin: "26.5 (.xcode-version)"), #"{"failures":[],"notes":[],"ok":false,"pin":"26.5 (.xcode-version)","pinNote":"xcrew: other Xcode"}"#),
        (.result, .init(note: "xcrew: other Xcode", pin: nil), #"{"failures":[],"notes":[],"ok":false,"pinNote":"xcrew: other Xcode"}"#),
    ])
    func eachStateIsWrittenUnderItsKeysAndReadBack(reading: Report.Reading, pinned: Report.PinNote?, written: String) throws {
        let report = Report(ok: false, failures: [], notes: [], reading: reading, pinned: pinned)
        #expect(try Self.json(report) == written)
        #expect(try JSONDecoder().decode(Report.self, from: Data(written.utf8)) == report)
    }
}
