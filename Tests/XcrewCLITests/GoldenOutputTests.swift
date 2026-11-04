import Foundation
import Testing
@testable import XcrewCLI
@testable import XcrewCore
import XcrewTestSupport

/// What each of the CLI's outputs the report's code reaches says for each test-bed capture, byte for byte, against a
/// golden recorded from the code before a change: `report` for every captured result and every captured log, `note`,
/// `why`, `look` and the evidence block, each with its exit status and what it wrote to standard error. A change that
/// means to move code without changing what it says leaves every golden as it is. The time is fixed, xcresulttool answers
/// from the files the test bed keeps beside each capture (`CaptureRunner`), and the temporary folders a run uses are
/// written as `<home>`, `<project>` and `<testbed>`. `XCREW_RECORD_GOLDENS=1` writes them; a golden is re-recorded only
/// with the reviewer's agreement.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct GoldenOutputTests {
    static let goldens = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Goldens")
    static let isRecording = ProcessInfo.processInfo.environment["XCREW_RECORD_GOLDENS"] == "1"
    static let captures = Testbed.root.appending(path: "captures")
    static let raw = captures.appending(path: "raw")
    static let field = captures.appending(path: "field")
    /// The day the goldens were first recorded, as every run's now.
    static let now = Date(timeIntervalSince1970: 1_793_750_400)

    /// One output: its golden's name, and how it's made.
    struct Output: Sendable, CustomTestStringConvertible {
        let name: String
        let make: @Sendable () async throws -> String
        var testDescription: String { name }
    }

    /// A run's own folders: a home and a project, each written as its placeholder, removed once the run is read.
    struct Place: Sendable {
        let root: URL
        let home: URL
        let project: Project

        init() throws {
            root = FileManager.default.temporaryDirectory.appending(path: "xcrew-golden-\(UUID().uuidString)")
            home = root.appending(path: "home")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            project = Project(root: root.appending(path: "project"))
            try FileManager.default.createDirectory(at: project.root, withIntermediateDirectories: true)
        }

        func machine(_ runner: any CommandRunning) -> Machine {
            Machine(environment: [:], home: home, runner: runner, processID: 1, applications: project.root.appending(path: "Applications"), now: { GoldenOutputTests.now })
        }

        /// What `argv` printed, its exit status and what it wrote to standard error, with this run's folders and the test
        /// bed's written as placeholders; the folders removed.
        func run(_ argv: [String], _ runner: any CommandRunning = FakeRunner(), project: Project? = nil, stdin: String = "") async -> String {
            let run = await Run(argv: argv, context: CheckContext(project: project ?? self.project, machine: machine(runner)), stdin: stdin)
            return neutral(run.text + "\n--- exit \(run.status)" + run.errors.map { "\nstderr: \($0)" }.joined())
        }

        /// `text` with this run's folders and the test bed's written as placeholders, as every machine spells them; the
        /// folders removed.
        func neutral(_ text: String) -> String {
            defer { try? FileManager.default.removeItem(at: root) }
            var neutral = text
            for (path, placeholder) in [(Testbed.root.path, "<testbed>"), (home.path, "<home>"), (project.root.path, "<project>")] {
                for spelling in Set([path, ProjectLayout.canonicalPath(path), path.replacingOccurrences(of: "/private/var/", with: "/var/")]) {
                    neutral = neutral.replacingOccurrences(of: spelling, with: placeholder)
                }
            }
            return neutral
        }
    }

    /// A raw capture's result text and whether it was an error, as the mod gets them.
    static func capture(_ name: String) throws -> (text: String, isError: Bool) {
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: raw.appending(path: "\(name).json"))) as? [String: Any])
        let text = (json["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined()
        return (text, json["isError"] as? Bool ?? false)
    }

    /// `xcrew report` for a captured result, as the mod asks for it, xcresulttool answering from `runner`.
    static func report(_ text: String, isError: Bool, kind: String, flags: [String], runner: (String?) throws -> any CommandRunning) async throws -> String {
        let place = try Place()
        let bundle = ResultBundle.path(in: ToolOutput(text: text, server: .mobileBuildMCP), home: place.home.path)
        return await place.run(["report", "--server", "MobileBuildMCP", "--kind", kind] + (isError ? ["--error"] : []) + flags, try runner(bundle), stdin: text)
    }

    /// The raw captures that are no build's, test's or run's result: what MobileBuildMCP's session tools answered.
    static let notReports: Set = ["capture", "session-defaults", "profile-switched"]
    /// The captures that are a build's, not a test run's.
    static let builds: Set = ["build_sim", "type-error"]
    /// The captures of runs repeated or retried, read with `--repeated`, as the mod reads them.
    static let repeated: Set = ["nested-retry", "retry", "shapes-iterations", "probes"]
    /// The field captures that are MobileBuildMCP's answer to something other than a build or test: `note`'s.
    static let noted: Set = ["two-display", "lldb-expr"]

    static func listing(_ folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    /// Each raw capture's name: its own result, not a file beside it.
    static var rawResults: [String] {
        listing(raw).filter { $0.hasSuffix(".json") && !$0.dropLast(5).contains(".") && !$0.hasSuffix("-snapshots.json") }.map { String($0.dropLast(5)) }
    }

    /// Each raw and field log, the live copies taken while a run went left out.
    static var logs: [(folder: URL, name: String)] {
        [raw, field].flatMap { folder in listing(folder).filter { $0.hasSuffix(".log") && !$0.hasSuffix("-midrun.log") }.map { (folder, String($0.dropLast(4))) } }
    }

    /// Each field capture's result text.
    static var fieldTexts: [String] {
        listing(field).filter { $0.hasSuffix(".txt") }.map { String($0.dropLast(4)) }
    }

    /// xcresulttool answering about `bundle` as `make` reads it, or answering nothing when there's no bundle.
    static func answering(_ bundle: String?, _ make: (String) throws -> CaptureRunner) rethrows -> any CommandRunning {
        guard let bundle else { return FakeRunner() }
        return try make(bundle)
    }

    /// xcresulttool answering about a raw capture's bundle from the files beside it.
    static func rawRunner(_ name: String) -> (String?) throws -> any CommandRunning {
        { bundle in try answering(bundle) { try CaptureRunner(name, in: raw, bundle: $0) } }
    }

    static func named(_ parts: [String], _ flags: [String]) -> String {
        (parts + flags.map { String($0.dropFirst(2)) }).joined(separator: "-")
    }

    static let outputs: [Output] = {
        var outputs: [Output] = []
        for name in rawResults where !notReports.contains(name) {
            let flags = repeated.contains(name) ? ["--repeated"] : []
            outputs.append(Output(name: named(["report", name], flags)) {
                let (text, isError) = try capture(name)
                return try await report(text, isError: isError, kind: builds.contains(name) ? "build" : "test", flags: flags, runner: rawRunner(name))
            })
        }
        for (name, flags) in [("serial", ["--passed"]), ("retry", ["--repeated", "--passed"])] {
            outputs.append(Output(name: named(["report", name], flags)) {
                let (text, isError) = try capture(name)
                return try await report(text, isError: isError, kind: "test", flags: flags, runner: rawRunner(name))
            })
        }
        for (folder, name) in logs {
            let flags = repeated.contains(name) ? ["--repeated"] : []
            outputs.append(Output(name: named(["report-log", folder.lastPathComponent, name], flags)) {
                let path = folder.appending(path: "\(name).log").path
                let bundle = RunLog.resultBundle(in: RunLog.text(ofLogAt: path))
                let runner: any CommandRunning = try answering(bundle) { try CaptureRunner(name, in: folder, bundle: $0) }
                return try await Place().run(["report", "--server", "MobileBuildMCP", "--kind", builds.contains(name) || name.hasPrefix("build") ? "build" : "test", "--log", path] + flags, runner)
            })
        }
        for name in fieldTexts where !noted.contains(name) {
            let flags = repeated.contains(name) ? ["--repeated"] : []
            outputs.append(Output(name: named(["report-field", name], flags)) {
                let text = try String(contentsOf: field.appending(path: "\(name).txt"), encoding: .utf8)
                return try await report(text, isError: text.contains("❌"), kind: builds.contains(name) ? "build" : "test", flags: flags) { bundle in
                    try answering(bundle) { try CaptureRunner(name, in: field, bundle: $0) }
                }
            })
        }
        for name in ["uitests", "snapshots"] {
            outputs.append(Output(name: "report-\(name)") {
                let text = try String(contentsOf: captures.appending(path: "\(name)/test_sim.txt"), encoding: .utf8)
                return try await report(text, isError: true, kind: "test", flags: []) { bundle in
                    try answering(bundle) { try CaptureRunner(folder: captures.appending(path: "\(name)/mobilebuildmcp"), bundle: $0) }
                }
            })
        }
        outputs.append(Output(name: "report-field-type-error-notification") {
            let text = try String(contentsOf: field.appending(path: "type-error.txt"), encoding: .utf8)
            return try await Place().run(["report", "--server", "MobileBuildMCP", "--kind", "build", "--notification"], stdin: BackgroundReportTests.notification(text))
        })
        outputs.append(Output(name: "report-serial-notification-passed") {
            let place = try Place()
            let (text, _) = try capture("serial")
            let bundle = ResultBundle.path(in: ToolOutput(text: text, server: .mobileBuildMCP), home: place.home.path)
            let runner: any CommandRunning = try answering(bundle) { try CaptureRunner("serial", in: raw, bundle: $0) }
            return await place.run(["report", "--server", "MobileBuildMCP", "--kind", "test", "--notification", "--passed"], runner, stdin: BackgroundReportTests.notification(text))
        })
        for name in noted.sorted() {
            outputs.append(Output(name: "note-\(name)") {
                let text = try String(contentsOf: field.appending(path: "\(name).txt"), encoding: .utf8)
                return try await Place().run(["note", "--server", "MobileBuildMCP", "--error"], stdin: text)
            })
        }
        let environment = captures.appending(path: "environment")
        for name in ["module-cache-malformed", "module-cache-invalid", "simulator-missing"] {
            outputs.append(Output(name: "why-log-\(name)") {
                try await Place().run(["why", "--log", environment.appending(path: "\(name).log").path], FakeRunner.simulators(["iPhone 17"]), project: Project(root: environment))
            })
            outputs.append(Output(name: "why-result-\(name)") {
                let text = try String(contentsOf: environment.appending(path: "\(name).txt"), encoding: .utf8)
                return try await Place().run(["why", "--server", "MobileBuildMCP"], FakeRunner.simulators(["iPhone 17"]), project: Project(root: environment), stdin: text)
            })
        }
        outputs.append(Output(name: "why-result-type-error") {
            let text = try String(contentsOf: field.appending(path: "type-error.txt"), encoding: .utf8)
            return try await Place().run(["why", "--server", "MobileBuildMCP"], FakeRunner.simulators(["iPhone 17"]), stdin: text)
        })
        for test in [nil, "UITests/testFailsAfterTaps", "UITests/testPlanA"] as [String?] {
            let suffix = test.map { "-" + $0.replacingOccurrences(of: "/", with: "-") } ?? ""
            outputs.append(Output(name: "look-uitests-xcodebuild" + suffix) {
                let place = try Place()
                let bundle = try TestbedLookTests.bundle("xcodebuild", root: place.root)
                return place.neutral(await Look.report(bundle: bundle, named: test, keptIn: place.home.appending(path: "images"), now: now))
            })
            outputs.append(Output(name: "look-uitests-mobilebuildmcp" + suffix) {
                let bundle = "/runs/UITests.xcresult"
                let runner = try CaptureRunner(folder: captures.appending(path: "uitests/mobilebuildmcp"), bundle: bundle)
                return try await Place().run(["look"] + (test.map { [$0] } ?? []) + ["--bundle", bundle], runner)
            })
        }
        let ran = TestbedEvidenceTests.ran
        for (name, earlier, outside) in [("evidence-coverage", false, false), ("evidence-coverage-two-runs-outside", true, true)] {
            outputs.append(Output(name: name) {
                let (project, context) = try TestbedEvidenceTests.project(committed: ran.addingTimeInterval(-3600), ran: ran, earlier: earlier ? ran.addingTimeInterval(-7200) : nil, earlierTests: earlier ? 3 : nil, outsideChanged: outside)
                defer { try? FileManager.default.removeItem(at: project.root.deletingLastPathComponent()) }
                let run = await Run(argv: ["evidence"], context: context, stdin: TestbedEvidenceTests.input)
                let text = run.text + "\n--- exit \(run.status)" + run.errors.map { "\nstderr: \($0)" }.joined()
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
        #expect(Data(made.utf8) == recorded, "\(output.name) differs from its golden, \(golden.lastPathComponent):\n--- now\n\(made)\n--- golden\n\(String(decoding: recorded, as: UTF8.self))")
    }

    /// Every golden is one an output makes: none is left behind by a renamed or removed output.
    @Test(.disabled(if: isRecording, "the goldens are being written")) func everyGoldenIsAnOutputs() throws {
        let recorded = Set(try FileManager.default.contentsOfDirectory(atPath: Self.goldens.path).filter { $0.hasSuffix(".txt") })
        #expect(recorded == Set(Self.outputs.map { "\($0.name).txt" }))
    }

    /// Every raw and field capture is read by an output, or named as no report's: a capture added to the test bed can't
    /// pass unheld.
    @Test func everyCaptureIsHeld() {
        let names = Set(Self.outputs.map(\.name))
        for name in Self.rawResults where !Self.notReports.contains(name) {
            #expect(names.contains { $0 == "report-\(name)" || $0.hasPrefix("report-\(name)-") }, "\(name) has no report output")
        }
        for name in Self.fieldTexts {
            #expect(names.contains { $0.hasPrefix("report-field-\(name)") || $0 == "note-\(name)" }, "field \(name) has no output")
        }
    }
}
