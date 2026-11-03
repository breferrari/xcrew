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
}
