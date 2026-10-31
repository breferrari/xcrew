import Foundation
import Testing
import XcrewCore
import XcrewTestSupport

/// The goldens the mod's replay tests stub the CLI with (`hooks/mod/replays.ts`): each raw MobileBuildMCP capture's joined
/// `content` text, as the mod gets it, and what `xcrew report` answers for it with no result bundle to read, as on CI. Each
/// is held to the capture, to the CLI as it now answers, and to MobileBuildMCP's own verdict and counts in the capture's
/// `structuredContent`, so a golden can't go stale or carry a wrong answer unnoticed. `scripts/replays.sh` rewrites them.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedReplayTests {
    static let names = ["serial", "swift-testing", "profile", "shapes"]
    static let goldens = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "hooks/mod/replays.ts")
    static let header = """
        /**
         * Each raw MobileBuildMCP capture of the test bed as the mod gets it, the joined text of the result's content, and what
         * `xcrew report` answers for it with no result bundle to read. Written by scripts/replays.sh; TestbedReplayTests holds
         * each answer to the CLI and to MobileBuildMCP's own counts.
         */

        """

    static func golden(_ name: String) throws -> [String: Any] {
        let source = try String(contentsOf: goldens, encoding: .utf8)
        let start = try #require(source.range(of: "export const replays = ")).upperBound
        let all = try #require(try JSONSerialization.jsonObject(with: Data(source[start...].utf8)) as? [String: Any])
        return try #require(all[name] as? [String: Any])
    }

    static func capture(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Testbed.root.appending(path: "captures/raw/\(name).json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The capture as the mod gets it, and what `xcrew report` answers for it on a home with no result bundle.
    static func replay(_ name: String) async throws -> [String: Any] {
        let capture = try capture(name)
        let parts = try #require(capture["content"] as? [[String: Any]])
        let text = parts.compactMap { $0["text"] as? String }.joined()
        let isError = capture["isError"] as? Bool ?? false
        let project = Project.temporary()
        let machine = Machine(environment: [:], home: URL(filePath: "/testbed/user"), runner: FakeRunner(), processID: 1, applications: project.root.appending(path: "Applications"))
        let run = await Run(argv: ["report", "--server", "MobileBuildMCP", "--kind", "test"] + (isError ? ["--error"] : []), context: CheckContext(project: project, machine: machine), stdin: text)
        let report = try JSONSerialization.jsonObject(with: Data(run.text.utf8))
        return ["isError": isError, "text": text, "report": report]
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["XCREW_RECORD_REPLAYS"] != nil, "rewrites the goldens"))
    func record() async throws {
        var replays: [String: Any] = [:]
        for name in Self.names { replays[name] = try await Self.replay(name) }
        let json = try JSONSerialization.data(withJSONObject: replays, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (Self.header + "export const replays = " + String(decoding: json, as: UTF8.self) + "\n").write(to: Self.goldens, atomically: true, encoding: .utf8)
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
