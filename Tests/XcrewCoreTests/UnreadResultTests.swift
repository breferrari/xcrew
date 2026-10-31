import Foundation
import Testing

@testable import XcrewCore
import XcrewTestSupport

/// A build or test call that answers with no outcome, as a call Claude moved to the background answers with a handle.
/// Claude Code's mod docs give no shape for that handle, so a text in no shape either server uses stands for it.
@Suite struct UnreadResultTests {
    static let handle = "Task bg-1 is running in the background; its result will arrive as a notification."

    func report(_ text: String, server: Server, kind: Report.Kind = .build, isError: Bool = false) async -> Report {
        await Report.make(kind: kind, output: ToolOutput(text: text, server: server, isError: isError), home: "/home", runner: FakeRunner())
    }

    @Test func aResultInNoShapeIsUnread() async {
        #expect(await report(Self.handle, server: .mobileBuildMCP).isUnread == true)
        #expect(await report(Self.handle, server: .xcode, kind: .test).isUnread == true)
    }

    /// An error is an outcome, and a run (an app launch) may well answer with nothing to read.
    @Test func anErrorOrARunIsNoUnreadResult() async {
        #expect(await report(Self.handle, server: .mobileBuildMCP, isError: true).isUnread == nil)
        #expect(await report(Self.handle, server: .mobileBuildMCP, kind: .run).isUnread == nil)
    }

    /// No real result either server gave reads as unread: the test for a handle is that the text has nothing of the
    /// server's own, not that it says no outcome, so a passing text result or a format change stays a result.
    @Test(arguments: ["mobileTestsFailed", "mobileTestsFailedUnlocated", "mobileTestsCrashedAndSkipped", "mobileTestsBuildFailed", "xcodeBuildPassed", "xcodeBuildFailed", "xcodeTestsPassed", "xcodeTestsFailed", "xcodeTestsBuildFailed"])
    func noCapturedResultIsUnread(_ name: String) async throws {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures/Reports"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let server: Server = name.hasPrefix("mobile") ? .mobileBuildMCP : .xcode
        for kind in [Report.Kind.build, .test] {
            #expect(await report(text, server: server, kind: kind).isUnread == nil, "\(name) as \(kind)")
        }
    }

    /// Nor does a real MobileBuildMCP result, as text or as its JSON.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"), arguments: ["build_sim", "swift-testing", "serial", "shapes", "profile", "empty-filter"])
    func noRawResultIsUnread(_ name: String) async throws {
        for text in [try Raw.text(name), try Raw.json(name)] {
            for kind in [Report.Kind.build, .test] {
                #expect(await report(text, server: .mobileBuildMCP, kind: kind).isUnread == nil, "\(name) as \(kind)")
            }
        }
    }

    /// Nor does a field scenario's.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"), arguments: ["type-error", "crash", "probes", "coverage", "empty-filter"])
    func noFieldResultIsUnread(_ name: String) async throws {
        for kind in [Report.Kind.build, .test] {
            #expect(await report(try Field.text(name), server: .mobileBuildMCP, kind: kind).isUnread == nil, "\(name) as \(kind)")
        }
    }

    @Test func aResultThatSaysAnOutcomeIsRead() async {
        let succeeded = #"{"schema":"mobilebuildmcp.output.build-result","data":{"summary":{"status":"SUCCEEDED"}}}"#
        #expect(await report(succeeded, server: .mobileBuildMCP).isUnread == nil)
    }
}
