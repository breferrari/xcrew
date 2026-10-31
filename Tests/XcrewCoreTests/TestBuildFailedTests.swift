import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// MobileBuildMCP's real test run whose test target doesn't build (`captures/raw/test-build-failed`): `❌ Test failed.`,
/// the compiler's error and its excerpt under Errors, and no count.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestBuildFailedTests {
    static let error = "cannot convert value of type 'String' to specified type 'Int'"

    @Test func itSaysTheBuildFailedAndNoTestRan() throws {
        #expect(try Raw.output("test-build-failed").summary == .init(ok: false, detail: "build failed, tests didn't run"))
        #expect(try Raw.output("test-build-failed").testTotal == nil)
    }

    /// The compiler's error is its one failure, by file and line, and no test: the ledger keeps tests only.
    @Test func itsFailureIsTheCompilersErrorAndNoTest() throws {
        #expect(try Raw.output("test-build-failed").failures == [.init(title: "ProbeTests.swift:39", message: Self.error)])
    }

    /// What `why` reads: the compiler's error once, its excerpt left out.
    @Test func whyReadsTheCompilersErrorOnce() throws {
        #expect(try Raw.output("test-build-failed").reportedErrors.map(\.message) == [Self.error])
    }
}
