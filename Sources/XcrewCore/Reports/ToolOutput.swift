import Foundation

/// What a build, test or run call came to, read once from the server's own output into the shape
/// it has. Each shape matches output captured from a real server (see
/// `Tests/XcrewCoreTests/Fixtures/Reports`); output in any other shape falls back to whether the
/// server reported a tool error, so a server update degrades the summary rather than breaking it.
public struct ToolOutput: Sendable {
    enum Shape: Sendable {
        /// MobileBuildMCP's JSON, which it returns when a build or test run succeeds.
        case mobileBuildMCPJSON(MobileBuildMCPResult)
        /// MobileBuildMCP's text, which it returns instead when one fails.
        case mobileBuildMCPText(MobileText)
        case xcodeMCPJSON(XcodeMCPResult)
        /// Anything but a JSON object from the Xcode MCP.
        case unrecognized
    }

    public let text: String
    public let server: Server
    public let isError: Bool
    let shape: Shape

    public init(text: String, server: Server, isError: Bool = false) {
        self.text = text
        self.server = server
        self.isError = isError
        shape = Self.shape(of: text, from: server)
    }

    init(_ text: MobileText, isError: Bool) {
        self.text = text.text
        server = .mobileBuildMCP
        self.isError = isError
        shape = .mobileBuildMCPText(text)
    }

    /// Every field is lenient, so decoding fails only when the text isn't a JSON object.
    static func shape(of text: String, from server: Server) -> Shape {
        let data = Data(text.utf8)
        switch server {
        case .mobileBuildMCP:
            guard let result = try? JSONDecoder().decode(MobileBuildMCPResult.self, from: data) else { return .mobileBuildMCPText(MobileText(text)) }
            return .mobileBuildMCPJSON(result)
        case .xcode:
            return (try? JSONDecoder().decode(XcodeMCPResult.self, from: data)).map(Shape.xcodeMCPJSON) ?? .unrecognized
        }
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
        /// Whether it is a failing test, which a later run can pass, rather than a compile error.
        public let isTest: Bool

        public init(title: String, message: String, where location: String? = nil, isTest: Bool = false) {
            self.title = title
            self.message = message
            self.where = location
            self.isTest = isTest
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
        case .unrecognized: nil
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
        case .unrecognized: nil
        }
    }

    /// How many tests a test run ran, from either server's counts.
    public var testTotal: Int? {
        switch shape {
        case let .mobileBuildMCPJSON(result): result.testTotal
        case let .xcodeMCPJSON(result): result.testTotal
        case let .mobileBuildMCPText(text): text.counts?.sum
        case .unrecognized: nil
        }
    }

    /// Every failure a run reported, from each shape `summary` reads; none for a passing run.
    public var failures: [Failure] {
        switch shape {
        case let .xcodeMCPJSON(result): result.failures
        case let .mobileBuildMCPText(text): text.failures
        case .mobileBuildMCPJSON, .unrecognized: []
        }
    }

    /// A compiler warning and, when the server names them, the file and line it fires at.
    struct Warning: Sendable, Hashable {
        let message: String
        let path: String?
        let line: Int?
    }

    /// Each distinct warning in either server's build or test result: one listed again at the same place is one.
    var warnings: [Warning] {
        let listed = switch shape {
        case let .xcodeMCPJSON(result): result.warnings
        case let .mobileBuildMCPText(text): Self.placed(text.warnings)
        case let .mobileBuildMCPJSON(result): Self.placed(Self.listed(result.data?.diagnostics?.warnings ?? []))
        case .unrecognized: [Warning]()
        }
        var seen = Set<Warning>()
        return listed.filter { seen.insert($0).inserted }
    }

    /// MobileBuildMCP's JSON warnings, each place read from its `/path:line`.
    static func listed(_ warnings: [MobileBuildMCPResult.Warning]) -> [RepeatedWarnings.Warning] {
        warnings.map { RepeatedWarnings.Warning(message: $0.message, location: $0.location.map(RepeatedWarnings.Location.init)) }
    }

    /// Each warning with its file and line, where it has them.
    static func placed(_ warnings: [RepeatedWarnings.Warning]) -> [Warning] {
        warnings.map { Warning(message: $0.message, path: $0.location?.path, line: $0.location?.line.flatMap { Int($0) }) }
    }

    /// Each error a failed build or test run reported.
    var reportedErrors: [ReportedError] {
        switch shape {
        case let .mobileBuildMCPText(text): text.reportedErrors
        case let .xcodeMCPJSON(result):
            result.realErrors.map { error in
                ReportedError(message: error.message ?? "", path: error.filePath, line: error.lineNumber.flatMap { Int($0.text) })
            }
        case .mobileBuildMCPJSON, .unrecognized: []
        }
    }

    /// The build log MobileBuildMCP names in a failed run's text, with `~` read as `home`.
    func buildLog(home: String) -> String? {
        mobileText?.buildLog.map { Self.expandingHome($0, home: home) }
    }

    /// A path MobileBuildMCP writes with `~` for the home folder, made absolute.
    static func expandingHome(_ path: String, home: String) -> String {
        path.hasPrefix("~") ? home + path.dropFirst() : path
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
        case let .mobileBuildMCPText(text): text.resultBundle
        case .xcodeMCPJSON, .unrecognized: nil
        }
    }

    /// A MobileBuildMCP test result without its per-test list, which is nearly all of a large run's
    /// result (127 of 130 KB for 959 tests): the summary, counts, failures and artifacts stay, and the
    /// list is pointed to in `savedPath`. Nil for anything else.
    public func compactTestResult(savedPath: String) -> String? {
        guard case let .mobileBuildMCPJSON(result) = shape, result.schema == MobileBuildMCPResult.testResultSchema else { return nil }
        return editingData { data in
            guard data["testCases"] is [Any] else { return false }
            // No count of its own: the list can be one short of the summary's counts, which come from the result bundle.
            data["testCases"] = "per-test list left out to keep this result short; the counts above are complete, and the full result is in \(savedPath)"
            return true
        }
    }

    /// The output with each repeated warning listed once, with its count and every place; nil when none repeats.
    func collapsingWarnings() -> ToolOutput? {
        switch shape {
        case let .mobileBuildMCPText(text):
            return text.collapsingWarnings().map { ToolOutput($0, isError: isError) }
        case let .mobileBuildMCPJSON(result):
            guard let warnings = result.data?.diagnostics?.warnings,
                  let groups = RepeatedWarnings.grouped(Self.listed(warnings))
            else { return nil }
            return editingData { data in
                guard var diagnostics = data["diagnostics"] as? [String: Any], let listed = diagnostics["warnings"] as? [[String: Any]], listed.count == warnings.count else { return false }
                let first = Dictionary(zip(warnings.map(\.message), listed)) { first, _ in first }
                diagnostics["warnings"] = groups.map { group in
                    var warning = first[group.message] ?? [:]
                    guard group.count > 1 else { return warning }
                    warning["count"] = group.count
                    warning["location"] = group.locations.isEmpty ? nil : RepeatedWarnings.locations(group.locations)
                    return warning
                }
                data["diagnostics"] = diagnostics
                return true
            }.map { ToolOutput(text: $0, server: server, isError: isError) }
        case .xcodeMCPJSON, .unrecognized:
            return nil
        }
    }

    /// The JSON with `edit` made to its `data` and everything else written back as it came, which editing
    /// the object rather than the model keeps; nil when `edit` makes none.
    private func editingData(_ edit: (inout [String: Any]) -> Bool) -> String? {
        guard var json = ResultBundle.parse(text) as? [String: Any], var data = json["data"] as? [String: Any], edit(&data) else { return nil }
        json["data"] = data
        guard let encoded = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(decoding: encoded, as: UTF8.self)
    }

    /// A failing test run's text without the passing tests it lists, which it counts instead.
    public var compactTestText: String? { mobileText?.compacted()?.text }

    static func milliseconds(_ seconds: Double) -> Int {
        Int((seconds * 1000).rounded())
    }

    static func basename(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? path
    }

    static func shorten(_ text: String) -> String {
        text.count > maxDetail ? "\(text.prefix(maxDetail - 1))…" : text
    }
}
