import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// A failing run's failures from its result bundle, on the test bed's real captures: each shape the bundle reports its
/// own way, its summary, failures, messages and places as the report gives them.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct BundleFailuresTests {
    /// The report on a raw capture, its bundle's reads answered by what `xcresulttool` answered about it.
    static func report(_ name: String, repeated: Bool = false) async throws -> Report {
        let bundle = try Raw.bundle(name)
        var responses: [String: CommandResult] = ["xcrun xcresulttool get test-results tests --path \(bundle) --compact": .init(status: 0, stdout: try Raw.file("\(name).tests.json"))]
        if let summary = try? Raw.file("\(name).summary.json") { responses["xcrun xcresulttool get test-results summary --path \(bundle) --compact"] = .init(status: 0, stdout: summary) }
        return await Report.make(kind: .test, output: try Raw.output(name), home: Captured.home, runner: FakeRunner(responses: responses), repeated: repeated)
    }

    static func lines(_ report: Report) -> [String] {
        [report.detail ?? "-"] + report.failures.map { "\($0.title) | \($0.message) | \($0.where ?? "-")" }
    }

    /// A test plan's configurations run by Swift Testing: the text lists no failure in a shape it can be read in, and the
    /// bundle gives it, the summary naming it as it names a failure the text lists.
    @Test func aFailureTheTextDoesntListIsTheBundles() async throws {
        #expect(Self.lines(try await Self.report("shapes-configurations")) == [
            "1 of 5 failed · ShapesTests/fails",
            #"ShapesTests/fails | Expectation failed: Kit.name == "Other" | ShapesTests.swift:10"#,
        ])
    }

    /// A crashed test is a failure the bundle words as the text does, with no place of its own.
    @Test func aCrashedTestIsTheBundlesFailure() async throws {
        #expect(Self.lines(try await Self.report("system-failure-crash")) == [
            "1 of 1 failed · AssertCrashTests/test_crash",
            "AssertCrashTests/test_crash | Crash: xctest at implicit closure #1 in AssertCrashTests.test_crash() | -",
        ])
    }

    /// An expected failure is no failure, nor is a test a retry passed.
    @Test func anExpectedFailureOrARetryThatPassedIsNoFailure() async throws {
        #expect(Self.lines(try await Self.report("serial")).dropFirst().map { String($0.prefix { $0 != " " }) } == ["ProbeTests/testFails", "ProbeTests/testFlaky"])
        #expect(Self.lines(try await Self.report("retry", repeated: true)).dropFirst().map { String($0.prefix { $0 != " " }) } == ["ProbeTests/testFails"])
    }
}
