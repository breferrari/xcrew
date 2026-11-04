import Foundation
import Testing
@testable import XcrewCLI
@testable import XcrewCore
import XcrewTestSupport

/// What each of the CLI's outputs the report's code reaches says for each test-bed capture, byte for byte, against a
/// golden recorded from the code before a change: `report` for every captured result and from every captured log, the
/// field captures, `note`, `why` and `look`. A change that means to move code without changing what it says leaves every
/// golden as it is. The time is fixed, xcresulttool answers from the files the test bed keeps beside each capture
/// (`CaptureRunner`), and the temporary folders a run uses are written as `<home>`, `<project>` and `<testbed>`.
/// `XCREW_RECORD_GOLDENS=1` writes them; a golden is re-recorded only with the reviewer's agreement.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct GoldenOutputTests {
    static let goldens = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Goldens")
    static let isRecording = ProcessInfo.processInfo.environment["XCREW_RECORD_GOLDENS"] != nil
    static let raw = Testbed.root.appending(path: "captures/raw")
    static let field = Testbed.root.appending(path: "captures/field")
    /// The day the goldens were first recorded, as every run's now.
    static let now = Date(timeIntervalSince1970: 1_793_750_400)

    /// One output: its golden's name, and how it's made.
    struct Output: Sendable, CustomTestStringConvertible {
        let name: String
        let make: @Sendable () async throws -> String
        var testDescription: String { name }
    }

    /// A run's own folders: a home, a project and the test bed, each written as its placeholder.
    struct Place: Sendable {
        let home: URL
        let project: Project

        init() throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "xcrew-golden-\(UUID().uuidString)")
            home = root.appending(path: "home")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            project = Project.temporary()
        }

        func machine(_ runner: any CommandRunning) -> Machine {
            Machine(environment: [:], home: home, runner: runner, processID: 1, applications: project.root.appending(path: "Applications"), now: { GoldenOutputTests.now })
        }

        /// `text` with this run's folders and the test bed's written as placeholders, as every machine spells them.
        func neutral(_ text: String) -> String {
            var neutral = text
            for (path, placeholder) in [(Testbed.root.path, "<testbed>"), (home.path, "<home>"), (project.root.path, "<project>")] {
                for spelling in Set([path, ProjectLayout.canonicalPath(path), path.replacingOccurrences(of: "/private/var/", with: "/var/")]) {
                    neutral = neutral.replacingOccurrences(of: spelling, with: placeholder)
                }
            }
            return neutral
        }
    }

    static func capture(_ name: String) throws -> (text: String, isError: Bool) {
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: raw.appending(path: "\(name).json"))) as? [String: Any])
        let text = (json["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined()
        return (text, json["isError"] as? Bool ?? false)
    }

    /// `xcrew report` for a captured result, as the mod asks for it.
    static func report(_ name: String, in folder: URL, text: String, isError: Bool, kind: String, flags: [String]) async throws -> String {
        let place = try Place()
        let bundle = ResultBundle.path(in: ToolOutput(text: text, server: .mobileBuildMCP), home: place.home.path)
        let runner: any CommandRunning = try bundle.map { try CaptureRunner(name, in: folder, bundle: $0) } ?? FakeRunner()
        let run = await Run(argv: ["report", "--server", "MobileBuildMCP", "--kind", kind] + (isError ? ["--error"] : []) + flags, context: CheckContext(project: place.project, machine: place.machine(runner)), stdin: text)
        return place.neutral(run.text)
    }

    static let rawResults: [(name: String, kind: String, flags: [String])] = [
        ("build_sim", "build", []), ("cancel", "test", []), ("configurations", "test", []), ("empty-filter", "test", []),
        ("nested", "test", []), ("nested-retry", "test", ["--repeated"]), ("parallel", "test", []), ("profile", "test", []),
        ("retry", "test", ["--repeated"]), ("serial", "test", []), ("serial", "test", ["--passed"]), ("shapes", "test", []),
        ("shapes-configurations", "test", []), ("shapes-iterations", "test", ["--repeated"]), ("swift-testing", "test", []),
        ("system-failure-crash", "test", []), ("test-build-failed", "test", []), ("timing", "test", []),
    ]

    static let outputs: [Output] = {
        var outputs = rawResults.map { name, kind, flags in
            Output(name: (["report", name] + flags.map { String($0.dropFirst(2)) }).joined(separator: "-")) {
                let (text, isError) = try capture(name)
                return try await report(name, in: raw, text: text, isError: isError, kind: kind, flags: flags)
            }
        }
        let logs = ((try? FileManager.default.contentsOfDirectory(atPath: raw.path)) ?? []).filter { $0.hasSuffix(".log") && !$0.hasSuffix("-midrun.log") }.sorted()
        outputs += logs.map { log in
            Output(name: "report-log-\(log.dropLast(4))") {
                let place = try Place()
                let run = await Run(argv: ["report", "--server", "MobileBuildMCP", "--kind", log.hasPrefix("build") ? "build" : "test", "--log", raw.appending(path: log).path], context: CheckContext(project: place.project, machine: place.machine(FakeRunner())))
                return place.neutral(run.text)
            }
        }
        outputs += [("probes", ["--repeated"]), ("crash", []), ("empty-filter", []), ("coverage", []), ("type-error", [])].map { name, flags in
            Output(name: (["report-field", name] + flags.map { String($0.dropFirst(2)) }).joined(separator: "-")) {
                let text = try String(contentsOf: field.appending(path: "\(name).txt"), encoding: .utf8)
                return try await report(name, in: field, text: text, isError: !text.contains("✅"), kind: name == "type-error" ? "build" : "test", flags: flags)
            }
        }
        outputs.append(Output(name: "report-field-type-error-notification") {
            let place = try Place()
            let text = try String(contentsOf: field.appending(path: "type-error.txt"), encoding: .utf8)
            let run = await Run(argv: ["report", "--server", "MobileBuildMCP", "--kind", "build", "--notification"], context: CheckContext(project: place.project, machine: place.machine(FakeRunner())), stdin: BackgroundReportTests.notification(text))
            return place.neutral(run.text)
        })
        outputs += ["two-display", "lldb-expr"].map { name in
            Output(name: "note-\(name)") {
                let text = try String(contentsOf: field.appending(path: "\(name).txt"), encoding: .utf8)
                let place = try Place()
                return place.neutral(await Run(argv: ["note", "--server", "MobileBuildMCP", "--error"], context: CheckContext(project: place.project, machine: place.machine(FakeRunner())), stdin: text).text)
            }
        }
        let environment = Testbed.root.appending(path: "captures/environment")
        for name in ["module-cache-malformed", "module-cache-invalid", "simulator-missing"] {
            outputs.append(Output(name: "why-log-\(name)") {
                let place = try Place()
                let context = CheckContext(project: Project(root: environment), machine: place.machine(FakeRunner.simulators(["iPhone 17"])))
                return place.neutral(await Run(argv: ["why", "--log", environment.appending(path: "\(name).log").path], context: context).text)
            })
            outputs.append(Output(name: "why-result-\(name)") {
                let place = try Place()
                let context = CheckContext(project: Project(root: environment), machine: place.machine(FakeRunner.simulators(["iPhone 17"])))
                let text = try String(contentsOf: environment.appending(path: "\(name).txt"), encoding: .utf8)
                return place.neutral(await Run(argv: ["why", "--server", "MobileBuildMCP"], context: context, stdin: text).text)
            })
        }
        for test in [nil, "UITests/testFailsAfterTaps", "UITests/testPlanA"] as [String?] {
            outputs.append(Output(name: "look-uitests" + (test.map { "-" + $0.replacingOccurrences(of: "/", with: "-") } ?? "")) {
                let place = try Place()
                let bundle = try TestbedLookTests.bundle("xcodebuild", root: place.home)
                return place.neutral(await Look.report(bundle: bundle, named: test, keptIn: place.home.appending(path: "images"), now: now))
            })
        }
        let ran = TestbedEvidenceTests.ran
        for (name, earlier, outside) in [("evidence-coverage", false, false), ("evidence-coverage-two-runs-outside", true, true)] {
            outputs.append(Output(name: name) {
                let (project, context) = try TestbedEvidenceTests.project(committed: ran.addingTimeInterval(-3600), ran: ran, earlier: earlier ? ran.addingTimeInterval(-7200) : nil, earlierTests: earlier ? 3 : nil, outsideChanged: outside)
                defer { try? FileManager.default.removeItem(at: project.root.deletingLastPathComponent()) }
                let text = await Run(argv: ["evidence"], context: context, stdin: TestbedEvidenceTests.input).text
                return text.replacingOccurrences(of: project.root.path, with: "<project>").replacingOccurrences(of: ProjectLayout.canonicalPath(project.root.path), with: "<project>")
            })
        }
        return outputs
    }()

    @Test(arguments: outputs) func eachOutputIsItsGolden(_ output: Output) async throws {
        let made = try await output.make()
        let golden = Self.goldens.appending(path: "\(output.name).txt")
        if Self.isRecording {
            try FileManager.default.createDirectory(at: Self.goldens, withIntermediateDirectories: true)
            try Data(made.utf8).write(to: golden)
            return
        }
        let recorded = try #require(try? Data(contentsOf: golden), "no golden for \(output.name): XCREW_RECORD_GOLDENS=1 records one")
        #expect(Data(made.utf8) == recorded, "\(output.name) differs from its golden:\n\(made)")
    }

    /// Every golden is one an output makes: none is left behind by a renamed or removed output.
    @Test(.disabled(if: isRecording, "the goldens are being written")) func everyGoldenIsAnOutputs() throws {
        let recorded = Set(try FileManager.default.contentsOfDirectory(atPath: Self.goldens.path).filter { $0.hasSuffix(".txt") })
        #expect(recorded == Set(Self.outputs.map { "\($0.name).txt" }))
    }
}
