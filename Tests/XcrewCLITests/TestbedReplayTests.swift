import Foundation
import Testing
import XcrewCore
import XcrewTestSupport

/// The goldens the mod's replay tests stub the CLI with (`hooks/mod/replays.ts`): each raw MobileBuildMCP capture's joined
/// `content` text, as the mod gets it, and what `xcrew report` answers for it, with xcresulttool's answers about its
/// result bundle read from the test bed. So CI needs no bundle. Each is held to the capture, to the CLI as it now
/// answers, and to MobileBuildMCP's own verdict and counts in the capture's `structuredContent`, so a golden can't go
/// stale or carry a wrong answer unnoticed. `scripts/replays.sh` rewrites them.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedReplayTests {
    static let names = ["serial", "swift-testing", "profile", "shapes"]
    static let goldens = Testbed.repository.appending(path: "hooks/mod/replays.ts")
    static let raw = Testbed.root.appending(path: "captures/raw")
    /// The home the captures' paths are neutralised to, which the bundle paths in the goldens name.
    static let home = "/testbed/user"
    static let header = """
        /**
         * Each raw MobileBuildMCP capture of the test bed as the mod gets it, the joined text of the result's content, and what
         * `xcrew report` answers for it, with xcresulttool's answers about its result bundle read from the test bed. Written
         * by scripts/replays.sh; TestbedReplayTests holds each answer to the CLI and to MobileBuildMCP's own counts.
         */

        """

    static func golden(_ name: String) throws -> [String: Any] {
        let source = try String(contentsOf: goldens, encoding: .utf8)
        let start = try #require(source.range(of: "export const replays = ")).upperBound
        let all = try #require(try JSONSerialization.jsonObject(with: Data(source[start...].utf8)) as? [String: Any])
        return try #require(all[name] as? [String: Any])
    }

    static func capture(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: raw.appending(path: "\(name).json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The capture as the mod gets it, and what `xcrew report` answers for it, with xcresulttool's answers about its result
    /// bundle read from the test bed.
    static func replay(_ name: String) async throws -> [String: Any] {
        let capture = try capture(name)
        let parts = try #require(capture["content"] as? [[String: Any]])
        let text = parts.compactMap { $0["text"] as? String }.joined()
        let isError = capture["isError"] as? Bool ?? false
        let project = Project.temporary()
        let machine = Machine(environment: [:], home: URL(filePath: home), runner: try runner(answering: name, text: text), processID: 1, applications: project.root.appending(path: "Applications"))
        let run = await Run(argv: ["report", "--server", "MobileBuildMCP", "--kind", "test"] + (isError ? ["--error"] : []), context: CheckContext(project: project, machine: machine), stdin: text)
        let report = try JSONSerialization.jsonObject(with: Data(run.text.utf8))
        return ["isError": isError, "text": text, "report": report]
    }

    /// What xcresulttool answered about the capture's result bundle, kept beside it in the test bed: the bundle's tests, its
    /// summary, and each failed or expected-to-fail test's details, by the id each names. Anything else isn't found.
    private static func runner(answering name: String, text: String) throws -> FakeRunner {
        let output = ToolOutput(text: text, server: .mobileBuildMCP)
        let bundle = try #require(ResultBundle.path(in: output, home: home))
        func answer(_ file: String) throws -> CommandResult {
            .init(status: 0, stdout: try String(contentsOf: raw.appending(path: file), encoding: .utf8))
        }
        var responses = [
            "xcrun xcresulttool get test-results tests --path \(bundle) --compact": try answer("\(name).tests.json"),
            "xcrun xcresulttool get test-results summary --path \(bundle) --compact": try answer("\(name).summary.json"),
        ]
        for file in try FileManager.default.contentsOfDirectory(atPath: raw.path) where file.hasPrefix("\(name).details.") {
            let details = try answer(file)
            let id = try #require((try JSONSerialization.jsonObject(with: Data(details.stdout.utf8)) as? [String: Any])?["testIdentifier"] as? String)
            responses["xcrun xcresulttool get test-results test-details --test-id \(id) --path \(bundle) --compact"] = details
        }
        return FakeRunner(responses: responses)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["XCREW_RECORD_REPLAYS"] != nil, "rewrites the goldens"))
    func record() async throws {
        var replays: [String: Any] = [:]
        for name in Self.names { replays[name] = try await Self.replay(name) }
        let json = try JSONSerialization.data(withJSONObject: replays, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (Self.header + "export const replays = " + String(decoding: json, as: UTF8.self) + "\n").write(to: Self.goldens, atomically: true, encoding: .utf8)
    }

    /// A retried test that passed on a later try is counted passed, though MobileBuildMCP's text still lists it among the
    /// failures: the report lists only the test that never passed, as its count does (1 failed).
    @Test func aRetriedTestThatPassedIsNoFailure() async throws {
        let report = try #require(try await Self.replay("retry")["report"] as? [String: Any])
        let failures = try #require(report["failures"] as? [[String: Any]])
        #expect(failures.compactMap { $0["title"] as? String } == ["ProbeTests/testFails"])
        #expect(report["detail"] as? String == "1 of 4 failed · ProbeTests/testFails")
    }

    @Test(arguments: names) func aGoldenIsItsCaptureAndWhatTheCLIAnswers(name: String) async throws {
        #expect(try NSDictionary(dictionary: Self.golden(name)) == NSDictionary(dictionary: await Self.replay(name)))
    }

    @Test(arguments: names) func aGoldensVerdictAndCountAreMobileBuildMCPs(name: String) throws {
        let report = try #require(try Self.golden(name)["report"] as? [String: Any])
        let summary = try #require(((try Self.capture(name))["structuredContent"] as? [String: Any]).flatMap { ($0["data"] as? [String: Any])?["summary"] as? [String: Any] })
        let counts = try #require(summary["counts"] as? [String: Int])
        let passed = try #require(counts["passed"]), failed = try #require(counts["failed"]), skipped = try #require(counts["skipped"])
        let detail = try #require(report["detail"] as? String)
        #expect(report["ok"] as? Bool == (summary["status"] as? String == "SUCCEEDED"))
        #expect(report["tests"] as? Int == passed + failed + skipped)
        #expect(failed == 0 ? detail == "\(passed) passed" : detail.hasPrefix("\(failed) of \(passed + failed + skipped) failed · "))
    }
}
