import Foundation

/// A report as the mod reads it (`Report` in hooks/mod/cli.ts): each field under its own key, absent when it's nil, and
/// `reading` and `pinned` as the keys they always had, so the JSON is the same whatever the type holds them as.
extension Report: Codable {
    enum CodingKeys: String, CodingKey {
        case ok, detail, durationMs, tests, failures, result, notes, repeated, passed, isUnread, bundle, pinNote, pin, backgroundTask, isVerdictOnly, cause, concurrency, scheme
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let reading: Reading = if try values.decodeIfPresent(Bool.self, forKey: .isVerdictOnly) == true {
            .verdictOnly
        } else if try values.decodeIfPresent(Bool.self, forKey: .isUnread) == true {
            .unread(task: try values.decodeIfPresent(String.self, forKey: .backgroundTask))
        } else {
            .result
        }
        let pinned = try values.decodeIfPresent(String.self, forKey: .pinNote).map { PinNote(note: $0, pin: try values.decodeIfPresent(String.self, forKey: .pin)) }
        self.init(
            ok: try values.decode(Bool.self, forKey: .ok),
            detail: try values.decodeIfPresent(String.self, forKey: .detail),
            durationMs: try values.decodeIfPresent(Int.self, forKey: .durationMs),
            tests: try values.decodeIfPresent(Int.self, forKey: .tests),
            failures: try values.decode([ToolOutput.Failure].self, forKey: .failures),
            result: try values.decodeIfPresent(String.self, forKey: .result),
            notes: try values.decode([String].self, forKey: .notes),
            repeated: try values.decodeIfPresent([ResultBundle.Repeated].self, forKey: .repeated),
            passed: try values.decodeIfPresent([PassedTest].self, forKey: .passed),
            reading: reading,
            bundle: try values.decodeIfPresent(String.self, forKey: .bundle),
            pinned: pinned,
            cause: try values.decodeIfPresent(String.self, forKey: .cause),
            concurrency: try values.decodeIfPresent(ConcurrencySummary.self, forKey: .concurrency),
            scheme: try values.decodeIfPresent(String.self, forKey: .scheme)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(ok, forKey: .ok)
        try values.encodeIfPresent(detail, forKey: .detail)
        try values.encodeIfPresent(durationMs, forKey: .durationMs)
        try values.encodeIfPresent(tests, forKey: .tests)
        try values.encode(failures, forKey: .failures)
        try values.encodeIfPresent(result, forKey: .result)
        try values.encode(notes, forKey: .notes)
        try values.encodeIfPresent(repeated, forKey: .repeated)
        try values.encodeIfPresent(passed, forKey: .passed)
        switch reading {
        case .result: break
        case let .unread(task):
            try values.encode(true, forKey: .isUnread)
            try values.encodeIfPresent(task, forKey: .backgroundTask)
        case .verdictOnly:
            try values.encode(true, forKey: .isVerdictOnly)
        }
        try values.encodeIfPresent(bundle, forKey: .bundle)
        try values.encodeIfPresent(pinned?.note, forKey: .pinNote)
        try values.encodeIfPresent(pinned?.pin, forKey: .pin)
        try values.encodeIfPresent(cause, forKey: .cause)
        try values.encodeIfPresent(concurrency, forKey: .concurrency)
        try values.encodeIfPresent(scheme, forKey: .scheme)
    }
}
