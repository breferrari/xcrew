import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// A Swift runtime error stops a test's process before XCTest records a message, so MobileBuildMCP lists it under Errors,
/// once plainly and once behind the xctest log's prefix (`captures/field/crash.txt`). It's the crashed test's own: its
/// crash note carries it, and the failures list the test, not two copies of its error. Any other error stays listed.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct CrashErrorTests {
    @Test func aCrashedTestsRuntimeErrorIsNoFailureOfItsOwn() throws {
        #expect(try Field.output("crash", isError: true).failures == [
            .init(title: "CrashTests/testOutOfRange", message: "Crash: xctest at CrashTests.testOutOfRange()", isTest: true),
        ])
    }

    /// The serial run with `showTestTiming` on lists the same error twice beside its other failing tests: its failures
    /// are its tests.
    @Test func aRunWithACrashAndOtherFailuresListsItsTestsAlone() throws {
        #expect(try Raw.output("timing").failures.map(\.title) == ["CrashTests/testOutOfRange", "ProbeTests/testFails", "ProbeTests/testFlaky"])
    }

    /// A crash inside an assertion's autoclosure, which a field run on iOS 26.5 saw filed under `System Failures`, is
    /// filed under its test on iOS 27.2 (`captures/raw/system-failure-crash`): xcrew names the test, and lists it alone.
    @Test func aCrashInsideAnAssertionIsNamedByItsTest() throws {
        let output = try Raw.output("system-failure-crash")
        #expect(output.summary == .init(ok: false, detail: "1 of 1 failed · AssertCrashTests/test_crash"))
        #expect(output.failures.map(\.title) == ["AssertCrashTests/test_crash"])
        #expect(output.failures.first?.message == "Crash: xctest at implicit closure #1 in AssertCrashTests.test_crash()")
    }

    /// The same crash filed under `System Failures`, as a field run on iOS 26.5 had it: MobileBuildMCP names the suite
    /// the result bundle gives, `System Failures`, and the test case it gives whole, `xctest (<pid>) encountered an
    /// error` (`utils/xcresult-test-failures.js:44-68`, `utils/renderers/domain-result-text.js:136-139`, MobileBuildMCP
    /// 2.7.1). Field shape, names neutralised: the 27.2 capture with its failure line written that way, its own pid.
    /// The message names the test, which is the crash's.
    @Test func aCrashFiledUnderSystemFailuresIsItsTestsFailure() throws {
        let filed = "  ✗ AssertCrashTests / test_crash(): Crash: xctest at implicit closure #1 in AssertCrashTests.test_crash()"
        let text = try Raw.text("system-failure-crash")
        #expect(text.contains(filed))
        let output = ToolOutput(text: text.replacingOccurrences(of: filed, with: "  ✗ System Failures / xctest (80341) encountered an error: Crash: xctest at implicit closure #1 in AssertCrashTests.test_crash()"), server: .mobileBuildMCP, isError: true)
        #expect(output.summary == .init(ok: false, detail: "1 of 1 failed · AssertCrashTests/test_crash"))
        #expect(output.failures == [.init(title: "AssertCrashTests/test_crash", message: "Crash: xctest at implicit closure #1 in AssertCrashTests.test_crash()", isTest: true)])
    }

    /// Another error in the same run, here a real one from `captures/environment/module-cache-invalid.txt` written
    /// into the crash's Errors, is still listed: only the crashed test's own error goes.
    @Test func anotherErrorBesideACrashStaysListed() throws {
        let other = "  ✗ missing required module 'SwiftShims'\n    <unknown>:0\n\n"
        let text = try Field.text("crash").replacingOccurrences(of: "Errors (2):\n\n", with: "Errors (3):\n\n" + other)
        let failures = ToolOutput(text: text, server: .mobileBuildMCP, isError: true).failures
        #expect(failures.contains { !$0.isTest && ($0.title + $0.message).contains("missing required module 'SwiftShims'") }, "\(failures)")
        #expect(!failures.contains { ($0.title + $0.message).contains("Fatal error: Index out of range") }, "\(failures)")
        #expect(failures.filter(\.isTest).map(\.title) == ["CrashTests/testOutOfRange"])
    }

    /// A second runtime error, at another place, is another process's or another file's, not the crashed test's: it
    /// stays listed though one test crashed. Built from the real error's line, its file and line moved
    /// (docs/findings.md, *A real test run's result*).
    @Test func anotherRuntimeErrorBesideACrashStaysListed() throws {
        let other = "  ✗ /testbed/field/Modules/Feature/Sources/Greeting.swift:15: Fatal error: Index out of range\n\n"
        let text = try Field.text("crash").replacingOccurrences(of: "Errors (2):\n\n", with: "Errors (3):\n\n" + other)
        let failures = ToolOutput(text: text, server: .mobileBuildMCP, isError: true).failures
        #expect(failures.filter { !$0.isTest }.map { $0.title + ": " + $0.message } == ["/testbed/field/Modules/Feature/Sources/Greeting.swift:15: Fatal error: Index out of range"], "\(failures)")
        #expect(failures.filter(\.isTest).map(\.title) == ["CrashTests/testOutOfRange"])
    }
}
