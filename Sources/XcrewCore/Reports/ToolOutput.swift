import Foundation

/// What a build, test or run call came to, read once from the server's own output into the shape
/// it has. Each shape matches output captured from a real server (see
/// `Tests/XcrewCoreTests/Fixtures/Reports`); output in any other shape falls back to whether the
/// server reported a tool error, so a server update degrades the summary rather than breaking it.
public struct ToolOutput: Sendable {
    enum Shape: Sendable {
        case mobileBuildMCPJSON(MobileBuildMCPResult)
        /// Any other JSON object: the Xcode MCP's, or one no reader knows.
        case xcodeMCPJSON(XcodeMCPResult)
        /// MobileBuildMCP's text, and anything else that isn't a JSON object.
        case mobileBuildMCPText(MobileText)
    }

    public let text: String
    public let isError: Bool
    let shape: Shape

    public init(text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
        shape = Self.shape(of: text)
    }

    init(_ text: MobileText, isError: Bool) {
        self.text = text.text
        self.isError = isError
        shape = .mobileBuildMCPText(text)
    }

    /// Every field is lenient, so decoding fails only when the text isn't a JSON object.
    static func shape(of text: String) -> Shape {
        let data = Data(text.utf8)
        guard let mobile = try? JSONDecoder().decode(MobileBuildMCPResult.self, from: data) else { return .mobileBuildMCPText(MobileText(text)) }
        if mobile.schema?.hasPrefix(MobileBuildMCPResult.schemaPrefix) == true { return .mobileBuildMCPJSON(mobile) }
        return (try? JSONDecoder().decode(XcodeMCPResult.self, from: data)).map(Shape.xcodeMCPJSON) ?? .mobileBuildMCPText(MobileText(text))
    }

    public struct Summary: Sendable, Equatable, Codable {
        public let ok: Bool
        public let detail: String?

        public init(ok: Bool, detail: String? = nil) {
            self.ok = ok
            self.detail = detail
        }
    }

    /// One failing test or compile error, for the failure pane.
    public struct Failure: Sendable, Equatable, Codable {
        public let title: String
        public let message: String
        public let `where`: String?

        public init(title: String, message: String, where location: String? = nil) {
            self.title = title
            self.message = message
            self.where = location
        }
    }

    /// Keeps the summary to one line.
    static let maxDetail = 100
    static let testsDidNotRun = "build failed, tests didn't run"
    /// A test run whose counts are all 0 reports SUCCEEDED; it's usually a filter that matched nothing.
    static let noTestsRan = "no tests ran"

    public var summary: Summary {
        let found: Summary? = switch shape {
        case let .mobileBuildMCPJSON(result): result.summary
        case let .xcodeMCPJSON(result): result.summary
        case let .mobileBuildMCPText(text): text.summary
        }
        guard let found else { return Summary(ok: !isError) }
        return Summary(ok: found.ok, detail: found.detail.map(Self.shorten))
    }

    /// How long the server says the run took, in milliseconds, which leaves out the hooks and
    /// permission prompts around the call: MobileBuildMCP's `durationMs` or its `(⏱️ 12.3s)`, the
    /// Xcode MCP's `elapsedTime`. The Xcode MCP's test runs report none.
    public var reportedDuration: Int? {
        switch shape {
        case let .mobileBuildMCPJSON(result): result.durationMs
        case let .xcodeMCPJSON(result): result.durationMs
        case let .mobileBuildMCPText(text): text.durationMs
        }
    }

    /// How many tests a test run ran, from either server's counts.
    public var testTotal: Int? {
        switch shape {
        case let .mobileBuildMCPJSON(result): result.testTotal
        case let .xcodeMCPJSON(result): result.testTotal
        case let .mobileBuildMCPText(text): text.counts.map { $0.failed + $0.passed + $0.skipped }
        }
    }

    /// Every failure a run reported, from each shape `summary` reads; none for a passing run.
    public var failures: [Failure] {
        switch shape {
        case .mobileBuildMCPJSON: []
        case let .xcodeMCPJSON(result): result.failures
        case let .mobileBuildMCPText(text): text.failures
        }
    }

    /// MobileBuildMCP's text, when the output is in that shape.
    var mobileText: MobileText? {
        if case let .mobileBuildMCPText(text) = shape { return text }
        return nil
    }

    /// The run's `.xcresult`, as MobileBuildMCP writes it: from a passing run's JSON, or the
    /// workspace folder and bundle path a failing run's text lists.
    var xcresultPath: String? {
        switch shape {
        case let .mobileBuildMCPJSON(result): result.data?.artifacts?.xcresultPath
        case .xcodeMCPJSON: nil
        case let .mobileBuildMCPText(text): text.resultBundle
        }
    }

    /// A MobileBuildMCP test result without its per-test list, which is nearly all of a large run's
    /// result (127 of 130 KB for 959 tests): the summary, counts, failures and artifacts stay, and the
    /// list is pointed to in `savedPath`. Nil for anything else.
    public func compactTestResult(savedPath: String) -> String? {
        // Everything else is written back as it came, so this edits the JSON object rather than the model.
        guard case let .mobileBuildMCPJSON(result) = shape, result.schema == MobileBuildMCPResult.testResultSchema,
              var json = Self.object(text), var data = json["data"] as? [String: Any], data["testCases"] is [Any]
        else { return nil }
        // No count of its own: the list can be one short of the summary's counts, which come from the result bundle.
        data["testCases"] = "per-test list left out to keep this result short; the counts above are complete, and the full result is in \(savedPath)"
        json["data"] = data
        guard let encoded = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(decoding: encoded, as: UTF8.self)
    }

    /// A failing test run's text without the passing tests it lists, which it counts instead.
    public var compactTestText: String? { mobileText?.compacted()?.text }

    /// A failing build's text without the compiler's copy of each error.
    public var cleanBuildText: String? { mobileText?.withoutExcerpts()?.text }

    static func object(_ text: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    static func basename(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? path
    }

    static func shorten(_ text: String) -> String {
        text.count > maxDetail ? "\(text.prefix(maxDetail - 1))…" : text
    }
}
