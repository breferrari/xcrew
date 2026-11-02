import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// The scheme a MobileBuildMCP run built, from the `Command line invocation:` its log opens with.
struct LogSchemeTests {
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"), arguments: [("serial.log", "Feature"), ("profile.log", "Data"), ("swift-testing.log", "Core")])
    func aRealLogNamesTheSchemeItBuilt(log: String, scheme: String) throws {
        #expect(RunLog.scheme(in: try Raw.file(log)) == scheme)
    }

    @Test func aQuotedSchemeIsReadWhole() {
        #expect(RunLog.scheme(in: "Command line invocation:\n    /x/xcodebuild -workspace /w/App.xcworkspace -scheme \"My App\" -destination \"platform=iOS Simulator\" test\n") == "My App")
    }

    @Test func aLogWithoutTheInvocationNamesNone() {
        #expect(RunLog.scheme(in: "Build settings from command line:\n\n** BUILD SUCCEEDED **\n") == nil)
        #expect(RunLog.scheme(in: "Command line invocation:\n    /x/xcodebuild -workspace /w/App.xcworkspace test\n") == nil)
    }

    /// MobileBuildMCP puts `-scheme` before the test filters, so a run selecting thousands of tests, whose invocation
    /// runs past the 64 KB read, still names its scheme (docs/findings.md, *How much of the log is read for the scheme*).
    @Test func aRunSelectingThousandsOfTestsStillNamesItsScheme() throws {
        let filters = (0..<3_000).map { " -only-testing:AppTests/CheckoutTests/testPaymentStep\($0)" }.joined()
        let log = "Command line invocation:\n    /x/xcodebuild -workspace /w/App.xcworkspace -scheme App -skipMacroValidation\(filters) build-for-testing\n"
        #expect(log.utf8.count > 65_536)
        let file = FileManager.default.temporaryDirectory.appending(path: "xcrew-scheme-\(UUID().uuidString).log")
        try log.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(RunLog.scheme(ofLogAt: file) == "App")
    }
}
