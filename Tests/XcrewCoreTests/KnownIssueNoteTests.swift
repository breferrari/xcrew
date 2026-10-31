import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// `xcresulttool` files a Swift Testing known issue (`withKnownIssue`) as an Expected Failure, as it does XCTest's
/// `XCTExpectFailure`; the note names the API the test used, read from the real runs' bundle answers.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct KnownIssueNoteTests {
    func notes(_ name: String) async throws -> [String] {
        let bundle = try Raw.bundle(name)
        let runner = FakeRunner(responses: [
            "xcrun xcresulttool get test-results summary --path \(bundle) --compact": .init(status: 0, stdout: try Raw.file("\(name).summary.json")),
            "xcrun xcresulttool get test-results tests --path \(bundle) --compact": .init(status: 0, stdout: try Raw.file("\(name).tests.json")),
        ])
        return await Report.make(kind: .test, output: try Raw.output(name), home: Captured.home, runner: runner).notes
    }

    @Test func aSwiftTestingKnownIssueIsNamedAsOne() async throws {
        let notes = try await notes("shapes")
        #expect(notes.contains("xcrew: 1 test also ran with a known issue (withKnownIssue): ShapesTests/knownIssue(). They count as neither passed nor failed in the result: 6 tests ran in all."), "\(notes)")
    }

    @Test func anXCTestExpectedFailureIsNamedAsOne() async throws {
        let notes = try await notes("serial")
        #expect(notes.contains("xcrew: 1 test also ran as an expected failure (XCTExpectFailure): ProbeTests/testExpectedFailure(). They count as neither passed nor failed in the result: 5 tests ran in all."), "\(notes)")
    }
}
