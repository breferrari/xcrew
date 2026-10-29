import Foundation

/// What a build, test or run call came to, read from the server's own output. Each reader matches
/// one shape captured from a real server (see `Tests/XcrewCoreTests/Fixtures/Reports`); output in any
/// other shape falls back to whether the server reported a tool error, so a server update degrades
/// the summary rather than breaking it.
public struct ToolOutput {
    public let text: String
    public let isError: Bool
    /// The text as a JSON object, when it is one: parsed once, since every reading below starts from it.
    let json: [String: Any]?

    public init(text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
        json = Self.object(text)
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
        let found = json.flatMap { Self.fromMobileBuildMCP($0) ?? Self.fromXcodeMCP($0) } ?? Self.fromMobileBuildMCPText(text) ?? Summary(ok: !isError)
        guard let detail = found.detail else { return found }
        return Summary(ok: found.ok, detail: Self.shorten(detail))
    }

    /// How long the server says the run took, in milliseconds, which leaves out the hooks and
    /// permission prompts around the call: MobileBuildMCP's `durationMs` or its `(⏱️ 12.3s)`, the
    /// Xcode MCP's `elapsedTime`. The Xcode MCP's test runs report none.
    public var reportedDuration: Int? {
        if let json {
            if let duration = (json["data"] as? [String: Any]).flatMap({ $0["summary"] as? [String: Any] })?["durationMs"] as? NSNumber {
                return duration.intValue
            }
            if let elapsed = json["elapsedTime"] as? NSNumber { return Int((elapsed.doubleValue * 1000).rounded()) }
            return nil
        }
        guard let seconds = text.firstMatch(of: #/\(⏱️ ([\d.]+)s\)/#).flatMap({ Double($0.1) }) else { return nil }
        return Int((seconds * 1000).rounded())
    }

    /// How many tests a test run ran, from either server's counts.
    public var testTotal: Int? {
        let nested = (json?["data"] as? [String: Any]).flatMap { $0["summary"] as? [String: Any] }?["counts"] as? [String: Any]
        if let counts = nested ?? json?["counts"] as? [String: Any] {
            if let total = counts["total"] as? Int { return total }
            return ["passed", "failed", "skipped"].reduce(0) { $0 + ((counts[$1] as? Int) ?? 0) }
        }
        guard let counts = MobileBuildMCPLine.counts(in: text) else { return nil }
        return counts.failed + counts.passed + counts.skipped
    }

    /// Every failure a run reported, from each shape `summary` reads; none for a passing run.
    public var failures: [Failure] {
        if let json { return Self.failuresFromXcodeMCP(json) }
        return Self.failuresFromMobileBuildMCPText(text)
    }

    static func object(_ text: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    /// MobileBuildMCP's JSON, which it returns when a build or test run succeeds.
    static func fromMobileBuildMCP(_ json: [String: Any]) -> Summary? {
        guard let schema = json["schema"] as? String, schema.hasPrefix("mobilebuildmcp.output."),
              let summary = (json["data"] as? [String: Any])?["summary"] as? [String: Any]
        else { return nil }
        let ok = summary["status"] as? String == "SUCCEEDED"
        guard let counts = summary["counts"] as? [String: Any] else { return Summary(ok: ok) }
        let passed = counts["passed"] as? Int ?? 0, failed = counts["failed"] as? Int ?? 0, skipped = counts["skipped"] as? Int ?? 0
        let total = passed + failed + skipped
        if total == 0 { return Summary(ok: false, detail: noTestsRan) }
        return failed > 0 ? Summary(ok: false, detail: "\(failed) of \(total) failed") : Summary(ok: ok, detail: "\(passed) passed")
    }

    /// The Xcode MCP's JSON: it reports failed builds and failed tests as normal results.
    static func fromXcodeMCP(_ json: [String: Any]) -> Summary? {
        if json["type"] as? String == "error" {
            let message = json["data"].map { "\($0)" } ?? ""
            if message.range(of: "build action failed", options: .caseInsensitive) != nil { return Summary(ok: false, detail: testsDidNotRun) }
            return Summary(ok: false, detail: message.isEmpty ? nil : message)
        }
        if let counts = json["counts"] as? [String: Any] {
            let passed = counts["passed"] as? Int ?? 0, failed = counts["failed"] as? Int ?? 0
            let total = counts["total"] as? Int
            if (total ?? passed + failed) == 0 { return Summary(ok: false, detail: noTestsRan) }
            if failed == 0 { return Summary(ok: true, detail: "\(passed) passed") }
            let results = json["results"] as? [[String: Any]] ?? []
            let first = results.first { $0["state"] as? String == "Failed" }?["identifier"] as? String
            return Summary(ok: false, detail: "\(failed) of \(total ?? failed) failed\(first.map { " · \($0)" } ?? "")")
        }
        if json["buildResult"] is String, let errors = json["errors"] as? [[String: Any]] {
            let real = errors.filter { $0["classification"] as? String != "warning" }
            guard let first = real.first else { return Summary(ok: true) }
            let location = (first["filePath"] as? String).map { "\(basename($0)):\(first["lineNumber"].map { "\($0)" } ?? "?") " } ?? ""
            let count = real.count > 1 ? "\(real.count) errors · " : ""
            return Summary(ok: false, detail: "\(count)\(location)\(first["message"] as? String ?? "")".trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// MobileBuildMCP's text, which it returns instead of JSON when a build or test run fails.
    static func fromMobileBuildMCPText(_ text: String) -> Summary? {
        let lines = text.components(separatedBy: "\n")
        if let counts = MobileBuildMCPLine.counts(in: text) {
            let first = lines.lazy.compactMap(MobileBuildMCPLine.failure).first
            return Summary(ok: false, detail: "\(counts.failed) of \(counts.failed + counts.passed + counts.skipped) failed\(first.map { " · \($0.test)" } ?? "")")
        }
        if text.hasPrefix("🧪"), text.contains("❌ Test failed") { return Summary(ok: false, detail: testsDidNotRun) }
        if text.contains("❌ Build failed") {
            // The first error MobileBuildMCP gives a location for.
            let first = lines.indices.dropLast().lazy.compactMap { index in
                MobileBuildMCPLine.entry(lines[index]).flatMap { entry in MobileBuildMCPLine.location(lines[index + 1]).map { (entry, $0) } }
            }.first
            guard let (entry, location) = first else { return Summary(ok: false) }
            return Summary(ok: false, detail: "\(basename(location.path)):\(location.line) \(entry)")
        }
        return nil
    }

    static func failuresFromXcodeMCP(_ json: [String: Any]) -> [Failure] {
        if let errors = json["errors"] as? [[String: Any]] {
            return errors.filter { $0["classification"] as? String != "warning" }.map { error in
                let title = (error["filePath"] as? String).map { "\(basename($0)):\(error["lineNumber"].map { "\($0)" } ?? "?")" } ?? "error"
                return Failure(title: title, message: error["message"] as? String ?? "")
            }
        }
        if let results = json["results"] as? [[String: Any]] {
            return results.filter { $0["state"] as? String == "Failed" }.map { result in
                let title = result["identifier"] as? String ?? "test"
                // `Tests/PlainTests.swift:5 PlainTests/testConcatenation(): XCTAssertEqual failed: …`
                let raw = (result["errorMessages"] as? [String])?.first ?? ""
                guard let located = raw.firstMatch(of: #/(?s)^(\S+?):(\d+) \S+?: (.*)$/#) else { return Failure(title: title, message: raw) }
                return Failure(title: title, message: String(located.3), where: "\(basename(String(located.1))):\(located.2)")
            }
        }
        return []
    }

    /// MobileBuildMCP's text: `✗ Suite / test: message` or `✗ message`, each maybe followed by its `/path:line`.
    static func failuresFromMobileBuildMCPText(_ text: String) -> [Failure] {
        let lines = text.components(separatedBy: "\n")
        var failures: [Failure] = []
        var seen: Set<String> = []
        for (index, line) in lines.enumerated() {
            // Its second copy of a compiler error is the source excerpt, drawn with `|`.
            guard let entry = MobileBuildMCPLine.entry(line), !entry.hasPrefix("|") else { continue }
            let path = index + 1 < lines.count ? MobileBuildMCPLine.location(lines[index + 1]) : nil
            let location = path.map { "\(basename($0.path)):\($0.line)" }
            if let test = MobileBuildMCPLine.test(in: entry) {
                let title = test.test
                // It lists a failing test twice, once with its location; the first is kept.
                guard seen.insert(title).inserted else { continue }
                // XCTest words an XCTFail as `failed - <message>`; the message is what was written.
                let message = test.message.replacing(#/^failed - /#, with: "")
                failures.append(Failure(title: title, message: message, where: location))
                continue
            }
            if let location {
                failures.append(Failure(title: location, message: entry))
                continue
            }
            if let split = entry.range(of: ": "), split.lowerBound > entry.startIndex {
                failures.append(Failure(title: String(entry[..<split.lowerBound]), message: String(entry[split.upperBound...])))
            } else {
                failures.append(Failure(title: entry, message: ""))
            }
        }
        return failures
    }

    static func basename(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? path
    }

    static func shorten(_ text: String) -> String {
        text.count > maxDetail ? "\(text.prefix(maxDetail - 1))…" : text
    }
}
