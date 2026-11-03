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

    /// The invocation is read wherever the log has it: lines before it, however many, don't hide its scheme.
    @Test func anInvocationPastTheLogsFirstLinesIsRead() throws {
        let before = String(repeating: "note: preparing\n", count: 200)
        let log = before + "Command line invocation:\n    /x/xcodebuild -workspace /w/App.xcworkspace -scheme Late test\n"
        #expect(RunLog.scheme(in: log) == "Late")
        let file = FileManager.default.temporaryDirectory.appending(path: "xcrew-scheme-\(UUID().uuidString).log")
        try (String(repeating: "x", count: 70_000) + "\n" + log).write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(RunLog.scheme(ofLogAt: file) == "Late")
        var reading = LogReading()
        reading.read(Data((log + "\n").utf8))
        #expect(reading.scheme == "Late")
    }

    /// The scheme is the run's own invocation's, the log's first: one that names none gives none, though a script the
    /// build ran starts another xcodebuild with a scheme later in the log.
    @Test func onlyTheFirstInvocationNamesTheScheme() throws {
        let log = "Command line invocation:\n    /x/xcodebuild -workspace /w/App.xcworkspace test\n" + String(repeating: "note: building\n", count: 100) + "Command line invocation:\n    /x/xcodebuild -project Vendor.xcodeproj -scheme Vendor build\n"
        #expect(RunLog.scheme(in: log) == nil)
        let file = FileManager.default.temporaryDirectory.appending(path: "xcrew-scheme-\(UUID().uuidString).log")
        try log.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(RunLog.scheme(ofLogAt: file) == nil)
        var reading = LogReading()
        reading.read(Data(log.utf8))
        #expect(reading.scheme == nil)
    }

    /// A finished run's verdict and result bundle are read wherever its log has them, however much follows.
    @Test func aVerdictFarFromTheLogsEndIsRead() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "xcrew-end-\(UUID().uuidString).log")
        try ("Test session results, code coverage, and logs:\n\t/b/Run.xcresult\n\n** TEST SUCCEEDED **\n" + String(repeating: "trailing output\n", count: 80_000)).write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(RunLog.resultBundle(in: RunLog.text(ofLogAt: file.path)) == "/b/Run.xcresult")
    }
}
