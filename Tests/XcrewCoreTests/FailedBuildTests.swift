import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// MobileBuildMCP's real failed build: the field fixture's plain type error (`captures/field/type-error.txt`), whose
/// text lists the compiler's error and then its excerpt of the line as a second error.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct FailedBuildTests {
    static let error = "cannot convert value of type 'String' to specified type 'Int'"

    @Test func aBuildGivesTheFirstErrorWithItsFileAndLine() throws {
        #expect(try Field.output("type-error", isError: true).summary == .init(ok: false, detail: "Greeting.swift:15 \(Self.error)"))
    }

    @Test func aBuildSaysHowLongItTook() throws {
        #expect(try Field.output("type-error").reportedDuration == 1_700)
    }

    @Test func aCompileErrorIsListedByFileAndLineAndIsNoTest() throws {
        let failures = try Field.output("type-error").failures
        #expect(failures == [.init(title: "Greeting.swift:15", message: Self.error)])
        #expect(failures.allSatisfy { !$0.isTest })
    }

    @Test func aBuildHasNoTestListToShortenAndNoBundle() throws {
        #expect(try Field.output("type-error").compactTestText == nil)
        #expect(ResultBundle.path(in: try Field.output("type-error"), home: Captured.home) == nil)
    }

    @Test func aCompileErrorIsCountedOnce() throws {
        let cleaned = try Field.output("type-error").mobileText?.withoutExcerpts()?.text ?? ""
        #expect(cleaned.contains("Errors (1):"))
        #expect(!cleaned.contains("✗ |"))
        #expect(cleaned.contains("✗ \(Self.error)\n    /testbed/field/Modules/Feature/Sources/Greeting.swift:15"))
    }

    @Test func aBuildFailureReachesClaudeWithItsErrorCountedOnce() async throws {
        let report = await Report.make(kind: .build, output: try Field.output("type-error", isError: true), home: Captured.home, runner: FakeRunner())
        #expect(report.result?.contains("Errors (1):") == true)
    }
}
