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
