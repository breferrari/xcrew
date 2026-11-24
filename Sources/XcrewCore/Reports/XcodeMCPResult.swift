import Foundation

/// The Xcode MCP's JSON: it reports failed builds, failed tests and failed runs as normal results. One type
/// reads all four shapes, an error, a test run's counts and results, a build's errors, and a run's result and its build's
/// errors.
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
    @Lenient var runResult: String?
    @Lenient var buildErrors: [BuildError]?
    @Lenient var processIdentifier: JSONText?
    @Lenient var elapsedTime: Double?

    /// The tests its results give as passed; nil when it gives no results. The Xcode MCP names no test bundle.
    var passedTests: [PassedTest]? {
        guard let results else { return nil }
        let identifiers = results.filter { $0.state == "Passed" }.compactMap(\.identifier)
        return identifiers.map { PassedTest(TestID(xcresultID: $0)) }.sorted()
    }

    /// A build's errors, or a run's build's.
    var allErrors: [BuildError]? { errors ?? buildErrors }

    /// The build's errors, without its warnings.
    var realErrors: [BuildError] { (allErrors ?? []).filter { !$0.isWarning } }

    /// Whether a run built and then launched nothing: what a scheme with no app to launch ends with, and an app that fails
    /// at launch too.
    var launchFailedAfterBuild: Bool { runResult?.contains("failed to launch after building successfully") == true }

    /// The build's warnings, each with its file and line where it has them.
    var warnings: [ToolOutput.Warning] {
        (allErrors ?? []).filter(\.isWarning).map { ToolOutput.Warning(message: $0.message ?? "", path: $0.filePath, line: $0.lineNumber.flatMap { Int($0.text) }) }
    }

    var summary: ToolOutput.Summary? {
        if type == "error" {
            let message = data?.text ?? ""
            if message.range(of: "build action failed", options: .caseInsensitive) != nil { return ToolOutput.Summary(ok: false, detail: ToolOutput.testsDidNotRun) }
            return ToolOutput.Summary(ok: false, detail: message.isEmpty ? nil : message)
        }
        if let runResult {
            if !realErrors.isEmpty { return errorsSummary }
            // A launched run names its process; the result's wording is Xcode's to change.
            return processIdentifier != nil ? ToolOutput.Summary(ok: true) : ToolOutput.Summary(ok: false, detail: runResult)
        }
        if let counts {
            let passed = counts.passed ?? 0, failed = counts.failed ?? 0
            if (counts.total ?? passed + failed) == 0 { return ToolOutput.Summary(ok: false, detail: ToolOutput.noTestsRan) }
            if failed == 0 { return ToolOutput.Summary(ok: true, detail: "\(passed) passed") }
            let first = results?.first { $0.state == "Failed" }?.identifier
            return .failing(failed, of: counts.total ?? failed, first: first)
        }
        if buildResult != nil, errors != nil { return errorsSummary }
        return nil
    }

    /// A build's verdict from its errors: a pass without any, else how many and the first.
    private var errorsSummary: ToolOutput.Summary {
        let real = realErrors
        guard let first = real.first else { return ToolOutput.Summary(ok: true) }
        let count = real.count > 1 ? "\(real.count) errors · " : ""
        let location = first.location.map { "\($0) " } ?? ""
        return ToolOutput.Summary(ok: false, detail: "\(count)\(location)\(first.message ?? "")".trimmingCharacters(in: .whitespaces))
    }

    var durationMs: Int? { elapsedTime.map(ToolOutput.milliseconds) }

    var testTotal: Int? {
        counts?.ran
    }

    var failures: [ToolOutput.Failure] {
        if allErrors != nil {
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
