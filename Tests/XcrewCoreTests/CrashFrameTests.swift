import Foundation
import Testing
@testable import XcrewCore

/// A crash names the test that crashed, or none: the frame its message ends on, whatever wraps it, and only a test the
/// run's list holds when there's a list; and the test's own line is its frame alone.
struct CrashFrameTests {
    /// A crash log whose crashed thread holds `frames`, each a symbol and its file and line, in the test bundle's image.
    static func log(_ frames: [(symbol: String, file: String, line: Int)]) -> String {
        let listed = frames.map { #"{"imageIndex":1,"symbol":"\#($0.symbol)","sourceFile":"/work/App/Tests/\#($0.file)","sourceLine":\#($0.line)}"# }.joined(separator: ",")
        return #"{"app_name":"xctest"}\#n{"faultingThread":0,"exception":{"type":"EXC_BREAKPOINT","signal":"SIGTRAP"},"usedImages":[{"name":"libswiftCore.dylib"},{"name":"AppTests"}],"threads":[{"frames":[{"imageIndex":0,"symbol":"_assertionFailure(_:_:file:line:flags:)"},\#(listed)]}]}"#
    }

    /// A suite whose name ends as the test's suite's does is another suite: its frame isn't the test's.
    @Test func aFrameInAnotherSuiteEndingTheSameIsntTheTests() {
        let log = Self.log([("AppTests.NotInner.test()", "NotInnerTests.swift", 7), ("AppTests.Inner.test()", "InnerTests.swift", 20)])
        #expect(ResultBundle.crashReport(log: log, test: TestID(suite: "Inner", name: "test()"))?.location == "InnerTests.swift:20")
    }

    /// A parameterised test's frame names its arguments' labels, `Suite.test(value:)`, and is its frame.
    @Test func aParameterisedTestsFrameIsItsOwn() {
        let log = Self.log([("AppTests.Helper.make()", "Helper.swift", 9), ("closure #1 in AppTests.Suite.test(value:)", "SuiteTests.swift", 31)])
        #expect(ResultBundle.crashReport(log: log, test: TestID(xcresultID: "Suite/test(value:)"))?.location == "SuiteTests.swift:31")
    }

    /// The frame a message ends on names the test however it's wrapped: an offset after it, an `@objc` thunk, an async
    /// test's resume function. An XCTest method needs no list: its name begins with `test`.
    @Test(arguments: [
        "Crash: xctest at Suite.testPop() + 40",
        "Crash: xctest at @objc Suite.testPop()",
        "Crash: xctest at (1) suspend resume partial function for Suite.testPop()",
        "Crash: xctest at implicit closure #1 in Suite.testPop()",
    ])
    func theTestIsReadThroughWhatWrapsItsFrame(message: String) {
        #expect(MobileBuildMCPLine.crashedTest(message: message) == TestID(suite: "Suite", name: "testPop()"))
    }

    /// Without a list, a helper the message ends on is no test, with arguments or without.
    @Test func withoutTheListAHelperIsNoTest() {
        #expect(MobileBuildMCPLine.crashedTest(message: "Crash: xctest at Cache.reset()") == nil)
        #expect(MobileBuildMCPLine.crashedTest(message: "Crash: xctest at Model.load(from:)") == nil)
    }

    /// A helper whose name doesn't begin with `test`, or a test of another overload, is no test the message names; a
    /// parameterised Swift Testing test, whose name XCTest's rule can't tell from a helper's, is none either.
    @Test func aHelperOrAParameterisedFrameNamesNoTest() {
        #expect(MobileBuildMCPLine.crashedTest(message: "Crash: xctest at Suite.parses()") == nil)
        #expect(MobileBuildMCPLine.crashedTest(message: "Crash: xctest at implicit closure #1 in Suite.test(value:)") == nil)
    }

    /// A process whose name holds " at " still names the test its message ends on.
    @Test func aProcessNameWithAtStillNamesTheTest() {
        #expect(MobileBuildMCPLine.crashedTest(message: "Crash: Look at Me at Suite.testPop()") == TestID(suite: "Suite", name: "testPop()"))
    }

    /// Another overload of the test's function is another test: its frame isn't the test's.
    @Test func anotherOverloadsFrameIsntTheTests() {
        let log = Self.log([("AppTests.Suite.test(other:)", "Other.swift", 3), ("AppTests.Suite.test(value:)", "SuiteTests.swift", 31)])
        #expect(ResultBundle.crashReport(log: log, test: TestID(xcresultID: "Suite/test(value:)"))?.location == "SuiteTests.swift:31")
    }
}
