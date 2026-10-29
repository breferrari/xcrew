import Foundation

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

    struct Warning: Decodable, Sendable {
        let message: String
        let location: String?
    }

    struct Diagnostics: Decodable, Sendable {
        @Lenient var warnings: [Warning]?
    }

    struct Payload: Decodable, Sendable {
        @Lenient var summary: Summary?
        @Lenient var artifacts: Artifacts?
        @Lenient var diagnostics: Diagnostics?
    }

    static let schemaPrefix = "mobilebuildmcp.output."
    static let testResultSchema = "mobilebuildmcp.output.test-result"

    @Lenient var schema: String?
    @Lenient var data: Payload?

    /// Its schema says which shape this is; without one, nothing is read as its summary.
    var summary: ToolOutput.Summary? {
        guard schema?.hasPrefix(Self.schemaPrefix) == true, let summary = data?.summary else { return nil }
        let ok = summary.status == "SUCCEEDED"
        guard let counts = summary.counts else { return ToolOutput.Summary(ok: ok) }
        let passed = counts.passed ?? 0, failed = counts.failed ?? 0, total = counts.sum
        if total == 0 { return ToolOutput.Summary(ok: false, detail: ToolOutput.noTestsRan) }
        return failed > 0 ? ToolOutput.Summary(ok: false, detail: "\(failed) of \(total) failed") : ToolOutput.Summary(ok: ok, detail: "\(passed) passed")
    }

    var durationMs: Int? { data?.summary?.durationMs.flatMap { Int(exactly: $0.rounded(.towardZero)) } }

    var testTotal: Int? {
        data?.summary?.counts?.ran
    }
}
