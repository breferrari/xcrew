import Foundation

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
        @Lenient var lineNumber: JSONText?
        @Lenient var message: String?

        var isWarning: Bool { classification == "warning" }
        /// `File.swift:12`, or `File.swift:?` when the error has no line.
        var location: String? { filePath.map { "\(ToolOutput.basename($0)):\(lineNumber?.text ?? "?")" } }
    }

    @Lenient var type: String?
    @Lenient var data: JSONText?
    @Lenient var counts: TestCounts?
    @Lenient var results: [TestResult]?
    @Lenient var buildResult: String?
    @Lenient var errors: [BuildError]?
    @Lenient var elapsedTime: Double?

    /// The build's errors, without its warnings.
    var realErrors: [BuildError] { (errors ?? []).filter { !$0.isWarning } }

    /// The build's warnings, each with its file and line where it has them.
    var warnings: [ToolOutput.Warning] {
        (errors ?? []).filter(\.isWarning).map { ToolOutput.Warning(message: $0.message ?? "", path: $0.filePath, line: $0.lineNumber.flatMap { Int($0.text) }) }
    }

    var summary: ToolOutput.Summary? {
        if type == "error" {
            let message = data?.text ?? ""
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
            guard let located = raw.firstMatch(of: #/(?s)^(\S+?):(\d+) \S+?: (.*)$/#) else { return ToolOutput.Failure(title: title, message: raw, isTest: true) }
            return ToolOutput.Failure(title: title, message: String(located.3), where: "\(ToolOutput.basename(String(located.1))):\(located.2)", isTest: true)
        }
    }
}
