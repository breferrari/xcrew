import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// A pull request's evidence: the block to paste, and apart from it the images to attach.
@Suite struct EvidenceTests {
    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13])
    /// 2026-10-30 14:24 UTC, in the mod's milliseconds.
    static let at = 1_793_370_240_000.0

    static func entry(_ test: String, message: String = "failed", green: Bool = true, bundle: String? = nil, flaky: (Int, Int)? = nil) -> String {
        let red = #"{"scope":"test_sim · App","at":\#(at),"message":"\#(message)"\#(bundle.map { #","bundle":"\#($0)""# } ?? "")}"#
        let passed = green ? #","green":{"scope":"test_sim · App","at":\#(at + 60_000)}"# : ""
        let marked = flaky.map { #","flaky":{"failed":\#($0.0),"runs":\#($0.1)}"# } ?? ""
        return #"{"test":"\#(test)","red":\#(red),"failing":"test_sim · App"\#(passed)\#(marked),"last":\#(at)}"#
    }

    static func input(_ entries: [String], times: [String] = []) throws -> EvidenceInput {
        let listed = times.map { #""\#($0)""# }.joined(separator: ",")
        return try JSONDecoder().decode(EvidenceInput.self, from: Data(#"{"ledger":[\#(entries.joined(separator: ","))],"times":[\#(listed)]}"#.utf8))
    }

    static func pack(_ input: EvidenceInput, project: Project = .temporary(), open: @escaping @Sendable (String) -> ResultBundle = { ResultBundle(path: $0, runner: FakeRunner()) }) async -> EvidencePack.Text? {
        await EvidencePack.make(input, project: project, machine: CheckContext.fake(project: project).machine, open: open)
    }

    @Test func testsTakenFromRedToGreenAndThoseStillRedAreListed() async throws {
        let text = try #require(await Self.pack(try Self.input([
            Self.entry("CardTests/testCard", message: "Snapshot does not match reference."),
            Self.entry("Suite/testOther", message: "XCTAssertEqual failed", green: false),
            Self.entry("Suite/testFlaky", green: false, flaky: (2, 5)),
        ], times: ["test_sim · App: usually 1m 20s, 312 tests"])))
        #expect(text.block == """
            ## Evidence

            Tests this branch took from red to green:
            - `CardTests/testCard`: failed in `test_sim · App` ("Snapshot does not match reference."), then passed in `test_sim · App`. Its images aren't known: its failing run was recorded before xcrew kept the run's result bundle.

            Still red:
            - `Suite/testOther`: "XCTAssertEqual failed"
            - `Suite/testFlaky`: "failed", flaky, failing 2 of 5 runs

            Usual run times:
            - test_sim · App: usually 1m 20s, 312 tests
            """)
        #expect(text.attach == nil)
    }

    /// The images of a red-to-green test's failing run, read again from its result bundle: named in the block by a label
    /// the person replaces, listed with their paths only outside it.
    @Test func aRedToGreenTestsImagesAreListedOutsideTheBlock() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "xcrew-tests-\(UUID().uuidString)")
        let red = root.appending(path: "test_sim_1.xcresult"), export = root.appending(path: "export")
        for folder in [red, export] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        for name in ["R", "F", "D"] { try Self.png.write(to: export.appending(path: name)) }
        try Data(#"[{"testIdentifier":"CardTests/testCard()","attachments":[{"exportedFileName":"D","suggestedHumanReadableName":"difference_2_U.png"},{"exportedFileName":"R","suggestedHumanReadableName":"reference_0_U.png"},{"exportedFileName":"F","suggestedHumanReadableName":"failure_1_U.png"}]}]"#.utf8)
            .write(to: export.appending(path: "manifest.json"))
        let project = Project.temporary()
        let text = try #require(await Self.pack(try Self.input([Self.entry("CardTests/testCard", bundle: red.path)]), project: project) {
            ResultBundle(path: $0, runner: FakeRunner(), exportFolder: { export })
        })
        #expect(text.block.contains("then passed in `test_sim · App`. Images from its failing run: attached below."), "\(text.block)")
        let kept = project.root.appending(path: "home/Library/Caches/xcrew/images/test_sim_1/CardTests/testCard")
        #expect(text.attach == """
            Images to attach (for you, not the PR):
            - `CardTests/testCard`, images from its failing run:
              \(kept.appending(path: "reference_0_U.png").path)
              \(kept.appending(path: "failure_1_U.png").path)
              \(kept.appending(path: "difference_2_U.png").path)
            """)
        #expect(!text.block.contains(kept.path))
    }

    @Test func aFailingRunWhoseBundleIsGoneSaysSo() async throws {
        let text = try #require(await Self.pack(try Self.input([Self.entry("CardTests/testCard", bundle: "/nonexistent/test_sim_1.xcresult")])))
        #expect(text.block.contains("then passed in `test_sim · App`. Its failing run's result bundle is gone, and its images with it."), "\(text.block)")
    }

    /// The block is pasted into a pull request: no path of this Mac, no id of its devices, no DerivedData.
    @Test func theBlockHoldsNoLocalPathOrDeviceID() async throws {
        let project = Project.temporary()
        let message = "XCTAssertEqual failed at \(project.root.path)/Tests/CardTests.swift:12 on 0A1B2C3D-0000-4000-8000-1234567890AB, see /Users/someone/Library/Developer/Xcode/DerivedData/App-abc/Logs/x.log"
        let text = try #require(await Self.pack(try Self.input([Self.entry("CardTests/testCard", message: message, green: false)]), project: project))
        #expect(text.block.contains("\"XCTAssertEqual failed at Tests/CardTests.swift:12 on <id>, see x.log\""), "\(text.block)")
        for leak in ["/Users/", "/private/", "DerivedData", project.root.path, "0A1B2C3D"] { #expect(!text.block.contains(leak), "\(leak)") }
    }

    /// Any absolute or home path, not only those under a known folder, is cut to its file's name.
    @Test func everyPathOutsideTheProjectIsCutToItsFileName() async throws {
        let message = "see ~/Library/Developer/MobileBuildMCP/workspaces/App-1/logs/build_sim_1.log and /usr/local/lib/tool/rules.yml, not Sources/App/Card.swift"
        let text = try #require(await Self.pack(try Self.input([Self.entry("CardTests/testCard", message: message, green: false)])))
        #expect(text.block.contains("\"see build_sim_1.log and rules.yml, not Sources/App/Card.swift\""), "\(text.block)")
    }

    /// A path in a `file://` URL is a path of this Mac too, and a physical device's id is 8 and 16 hex digits.
    @Test func aFileURLsPathAndADevicesIDAreScrubbed() async throws {
        let message = "see file:///Users/someone/Library/Developer/Xcode/DerivedData/App-abc/Logs/shot.png on 00008110-001A2B3C4D5E801E"
        let text = try #require(await Self.pack(try Self.input([Self.entry("CardTests/testCard", message: message, green: false)])))
        #expect(text.block.contains("\"see shot.png on <id>\""), "\(text.block)")
    }

    @Test func aBranchWithNothingToSayGivesNoBlock() async throws {
        #expect(await Self.pack(try Self.input([])) == nil)
    }

    @Test func coverageOrWarningsFromARunOlderThanTheLastCommitSaySo() {
        let run = Date(timeIntervalSince1970: Self.at / 1000), commit = run.addingTimeInterval(36 * 60)
        #expect(EvidencePack.when("the test run", at: run, lastCommit: commit) == "From the test run of 2026-10-30 14:24 UTC, older than the branch's last commit (2026-10-30 15:00 UTC)")
        #expect(EvidencePack.when("the test run", at: commit, lastCommit: run) == "From the test run of 2026-10-30 15:00 UTC")
        #expect(EvidencePack.when("the build", at: run, lastCommit: nil) == "From the build of 2026-10-30 14:24 UTC")
    }
}

/// The ledger keeps a red run's result bundle, which the report names.
@Suite struct ReportBundleTests {
    @Test func aTestRunsReportNamesItsResultBundle() async {
        let output = #"{"schema":"mobilebuildmcp.output.test-result","didError":false,"data":{"summary":{"status":"SUCCEEDED"},"artifacts":{"xcresultPath":"~/runs/test_sim_1.xcresult"}}}"#
        let report = await Report.make(kind: .test, output: ToolOutput(text: output, server: .mobileBuildMCP), home: "/home", runner: FakeRunner())
        #expect(report.bundle == "/home/runs/test_sim_1.xcresult")
        let build = await Report.make(kind: .build, output: ToolOutput(text: output, server: .mobileBuildMCP), home: "/home", runner: FakeRunner())
        #expect(build.bundle == nil)
    }
}
