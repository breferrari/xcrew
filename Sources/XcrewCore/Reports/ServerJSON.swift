import Foundation

/// A field read as nil when it's missing or of another type, so one odd field doesn't lose the rest:
/// a server update degrades what's read from its output rather than breaking it.
@propertyWrapper
struct Lenient<Value: Decodable & Sendable>: Decodable, Sendable {
    var wrappedValue: Value?

    init(wrappedValue: Value? = nil) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: any Decoder) throws {
        wrappedValue = try? decoder.singleValueContainer().decode(Value.self)
    }
}

extension KeyedDecodingContainer {
    func decode<Value>(_ type: Lenient<Value>.Type, forKey key: Key) throws -> Lenient<Value> {
        try decodeIfPresent(type, forKey: key) ?? Lenient()
    }
}

/// A test run's counts, as both servers' JSON gives them.
struct TestCounts: Decodable, Sendable {
    @Lenient var passed: Int?
    @Lenient var failed: Int?
    @Lenient var skipped: Int?
    @Lenient var total: Int?

    init(passed: Int?, failed: Int?, skipped: Int?, total: Int? = nil) {
        _passed = Lenient(wrappedValue: passed)
        _failed = Lenient(wrappedValue: failed)
        _skipped = Lenient(wrappedValue: skipped)
        _total = Lenient(wrappedValue: total)
    }

    var sum: Int { (passed ?? 0) + (failed ?? 0) + (skipped ?? 0) }
    /// How many tests ran: the total when the server gives one.
    var ran: Int { total ?? sum }
}

/// MobileBuildMCP's JSON, which it returns when a build or test run succeeds:
/// `{"schema": "mobilebuildmcp.output.test-result", "data": {"summary": …, "artifacts": …}}`.
struct MobileBuildMCPResult: Decodable, Sendable {
    struct Summary: Decodable, Sendable {
        @Lenient var status: String?
        @Lenient var counts: TestCounts?
        @Lenient var durationMs: Double?
    }

    struct Artifacts: Decodable, Sendable {
        @Lenient var xcresultPath: String?
    }

    struct Payload: Decodable, Sendable {
        @Lenient var summary: Summary?
        @Lenient var artifacts: Artifacts?
    }

    static let schemaPrefix = "mobilebuildmcp.output."
    static let testResultSchema = "mobilebuildmcp.output.test-result"

    @Lenient var schema: String?
    @Lenient var data: Payload?

    var summary: ToolOutput.Summary? {
        guard let summary = data?.summary else { return nil }
        let ok = summary.status == "SUCCEEDED"
        guard let counts = summary.counts else { return ToolOutput.Summary(ok: ok) }
        let passed = counts.passed ?? 0, failed = counts.failed ?? 0, total = counts.sum
        if total == 0 { return ToolOutput.Summary(ok: false, detail: ToolOutput.noTestsRan) }
        return failed > 0 ? ToolOutput.Summary(ok: false, detail: "\(failed) of \(total) failed") : ToolOutput.Summary(ok: ok, detail: "\(passed) passed")
    }

    var durationMs: Int? { data?.summary?.durationMs.map { Int($0) } }

    var testTotal: Int? {
        data?.summary?.counts?.ran
    }
}

/// The Xcode MCP's JSON: it reports failed builds and failed tests as normal results. One type
/// reads all three shapes, an error, a test run's counts and results, and a build's errors.
struct XcodeMCPResult: Decodable, Sendable {
    struct TestResult: Decodable, Sendable {
        @Lenient var identifier: String?
        @Lenient var state: String?
        @Lenient var errorMessages: [String]?
    }

    struct BuildError: Decodable, Sendable {
        @Lenient var classification: String?
        @Lenient var filePath: String?
        @Lenient var lineNumber: Int?
        @Lenient var message: String?

        var isWarning: Bool { classification == "warning" }
        /// `File.swift:12`, or `File.swift:?` when the error has no line.
        var location: String? { filePath.map { "\(ToolOutput.basename($0)):\(lineNumber.map(String.init) ?? "?")" } }
    }

    @Lenient var type: String?
    @Lenient var data: String?
    @Lenient var counts: TestCounts?
    @Lenient var results: [TestResult]?
    @Lenient var buildResult: String?
    @Lenient var errors: [BuildError]?
    @Lenient var elapsedTime: Double?

    /// The build's errors, without its warnings.
    var realErrors: [BuildError] { (errors ?? []).filter { !$0.isWarning } }

    var summary: ToolOutput.Summary? {
        if type == "error" {
            let message = data ?? ""
            if message.range(of: "build action failed", options: .caseInsensitive) != nil { return ToolOutput.Summary(ok: false, detail: ToolOutput.testsDidNotRun) }
            return ToolOutput.Summary(ok: false, detail: message.isEmpty ? nil : message)
        }
        if let counts {
            let passed = counts.passed ?? 0, failed = counts.failed ?? 0
            if (counts.total ?? passed + failed) == 0 { return ToolOutput.Summary(ok: false, detail: ToolOutput.noTestsRan) }
            if failed == 0 { return ToolOutput.Summary(ok: true, detail: "\(passed) passed") }
            let first = results?.first { $0.state == "Failed" }?.identifier
            return ToolOutput.Summary(ok: false, detail: "\(failed) of \(counts.total ?? failed) failed\(first.map { " · \($0)" } ?? "")")
        }
        if buildResult != nil, errors != nil {
            let real = realErrors
            guard let first = real.first else { return ToolOutput.Summary(ok: true) }
            let count = real.count > 1 ? "\(real.count) errors · " : ""
            let location = first.location.map { "\($0) " } ?? ""
            return ToolOutput.Summary(ok: false, detail: "\(count)\(location)\(first.message ?? "")".trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    var durationMs: Int? { elapsedTime.map(ToolOutput.milliseconds) }

    var testTotal: Int? {
        counts?.ran
    }

    var failures: [ToolOutput.Failure] {
        if errors != nil {
            return realErrors.map { ToolOutput.Failure(title: $0.location ?? "error", message: $0.message ?? "") }
        }
        return (results ?? []).filter { $0.state == "Failed" }.map { result in
            let title = result.identifier ?? "test"
            // `Tests/PlainTests.swift:5 PlainTests/testConcatenation(): XCTAssertEqual failed: …`
            let raw = result.errorMessages?.first ?? ""
            guard let located = raw.firstMatch(of: #/(?s)^(\S+?):(\d+) \S+?: (.*)$/#) else { return ToolOutput.Failure(title: title, message: raw) }
            return ToolOutput.Failure(title: title, message: String(located.3), where: "\(ToolOutput.basename(String(located.1))):\(located.2)")
        }
    }
}
