import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// A build that failed because of the Mac, not the code: the cause, read from the errors and the Mac, and its fix; and
/// nothing at all for an error the code made, however alike its words.
@Suite struct WhyTests {
    /// MobileBuildMCP's result after one of Clang's cached modules was cut short (the test bed's
    /// `captures/environment/module-cache-malformed`, trimmed to its first errors).
    static let malformed = """

        🔨 Build

        Errors (3):

          ✗ Clang dependency scanning failure: While building module 'Dispatch' imported from module-include.input:1:

          ✗ malformed or corrupted precompiled file: 'can't skip to bit 95328 from 96'
            /Applications/Xcode-27.2.0-Beta.3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator27.2.sdk/usr/include/dispatch/dispatch.h:28

          ✗ could not build module 'Dispatch'
            (in target 'App' from project 'App')

        ❌ Build failed. (⏱️ 2.2s)
          └ Files:
             └── ~/Library/Developer/MobileBuildMCP/workspaces/environment-f963804cb4be/logs/build_sim_2026-10-30T07-31-02-114Z_pid18611_8a4c3d1e.log — Build Logs
        """

    /// After one of the SDK's precompiled modules was cut short (`module-cache-invalid`).
    static let invalid = """

        🔨 Build

        Errors (2):

          ✗ file '/testbed/DerivedData/SDKExplicitPrecompiledModules/SwiftShims-44J58ATYTB5F8RWZHD1OXEBAB.pcm' is not a valid module file: file too small to contain precompiled file magic
            truncated or malformed object (offset field plus size field of section 1 in LC_SEGMENT_64 command 0 extends past the end of the file)<unknown>:0

          ✗ missing required module 'SwiftShims'
            <unknown>:0

        ❌ Build failed. (⏱️ 2.0s)
        """

    /// For an iPhone name no simulator has (`simulator-missing`).
    static let missingSimulator = """

        🔨 Build

        Errors (1):

          ✗ Unable to find a device matching the provided destination specifier:
            { platform:iOS Simulator, OS:latest, name:iPhone 1 }

        ❌ Build failed. (⏱️ 61.2s)
        """

    func note(_ text: String, project: Project = .temporary(), home: URL? = nil, simulators: [String] = ["iPhone 17"]) async -> String? {
        let runner = FakeRunner.simulators(simulators)
        let home = home ?? project.root
        let output = ToolOutput(text: text, server: .mobileBuildMCP, isError: true)
        return await Why.note(for: output, home: home.path, project: project, runner: runner)
    }

    /// A build log under the fake home, where the result says MobileBuildMCP wrote it.
    func home(withLog log: String, named name: String) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "xcrew-why-\(UUID().uuidString)")
        let file = home.appending(path: "Library/Developer/MobileBuildMCP/workspaces/environment-f963804cb4be/logs/\(name)")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try log.write(to: file, atomically: true, encoding: .utf8)
        return home
    }

    /// The DerivedData folder comes from the build log the result names.
    @Test func aCorruptCachedModuleNamesTheFoldersToRemove() async throws {
        let log = "/usr/bin/xcrun xcodebuild -project App.xcodeproj -scheme App -derivedDataPath /testbed/DerivedData -destination id=A build\n"
        let home = try home(withLog: log, named: "build_sim_2026-10-30T07-31-02-114Z_pid18611_8a4c3d1e.log")
        #expect(await note(Self.malformed, home: home) == "xcrew: this build failed because of the Mac, not the code: a module in its DerivedData's module cache is corrupt (\"malformed or corrupted precompiled file\"). Remove the cached modules, then build again: rm -rf '/testbed/DerivedData/ModuleCache.noindex' '/testbed/DerivedData/SDKExplicitPrecompiledModules'")
    }

    /// Without the log, the fix names the folders inside the DerivedData the build used.
    @Test func withoutTheLogTheFoldersAreNamedInTheBuildsDerivedData() async {
        #expect(await note(Self.malformed) == "xcrew: this build failed because of the Mac, not the code: a module in its DerivedData's module cache is corrupt (\"malformed or corrupted precompiled file\"). Remove ModuleCache.noindex and SDKExplicitPrecompiledModules from the DerivedData this build used, then build again")
    }

    /// The module the error names sits in the DerivedData, which says where it is.
    @Test func anInvalidPrecompiledModuleNamesItsDerivedData() async {
        #expect(await note(Self.invalid) == "xcrew: this build failed because of the Mac, not the code: a module in its DerivedData's module cache is corrupt (\"SwiftShims-44J58ATYTB5F8RWZHD1OXEBAB.pcm is not a valid module file\"). Remove the cached modules, then build again: rm -rf '/testbed/DerivedData/ModuleCache.noindex' '/testbed/DerivedData/SDKExplicitPrecompiledModules'")
    }

    @Test func aSimulatorNoneHasNamesSetup() async {
        #expect(await note(Self.missingSimulator) == "xcrew: this build failed because of the Mac, not the code: no simulator here is named iPhone 1, which the build asked for. /xcrew:setup writes the profiles again with simulators that are installed")
    }

    /// The simulator is there, so something else kept the build from it: no guess.
    @Test func aSimulatorThatIsThereExplainsNothing() async {
        #expect(await note(Self.missingSimulator, simulators: ["iPhone 1"]) == nil)
    }

    /// A simulator list that couldn't be read is no evidence the simulator is gone.
    @Test func aSimulatorListThatFailedExplainsNothing() async {
        let output = ToolOutput(text: Self.missingSimulator, server: .mobileBuildMCP, isError: true)
        let failed = FakeRunner(responses: ["xcrun simctl list devices available --json": .init(status: 124, stdout: "")])
        #expect(await Why.note(for: output, home: "/home", project: .temporary(), runner: failed) == nil)
    }

    /// The fix keeps the profiles setup wrote: `/xcrew:setup` rewrites them all, where `xcrew setup` with one option
    /// would write the unit profile alone.
    @Test func aSimulatorThatIsGoneIsFixedThroughSetup() async throws {
        let note = try #require(await note(Self.missingSimulator))
        #expect(note.hasSuffix("/xcrew:setup writes the profiles again with simulators that are installed"))
        #expect(!note.contains("--test-simulator"))
    }

    // MARK: Reading a build log

    /// A project in a folder with a space: its own error stays its own, however alike its words.
    @Test func anErrorAtAPathWithASpaceIsTheCodes() async {
        let project = Project.temporary(containing: ["My App/Cache.swift"])
        let log = "\(project.root.path)/My App/Cache.swift:3:1: error: malformed or corrupted precompiled file: 'quoted'\n"
        let failure = FailureEvidence(errors: BuildLog.errors(in: log), project: project, runner: FakeRunner()) { nil }
        #expect(await Why.note(for: failure) == nil)
    }

    /// xcodebuild escapes a space in the path it was given; the fix quotes the folder for the shell.
    @Test(arguments: [
        (#"-derivedDataPath /Users/dev/My\ Builds/DD -destination"#, "/Users/dev/My Builds/DD"),
        (#"-derivedDataPath "/Users/dev/My Builds/DD" -destination"#, "/Users/dev/My Builds/DD"),
        ("-derivedDataPath /Users/dev/DD -destination", "/Users/dev/DD"),
    ])
    func theDerivedDataComesFromTheLogAsWritten(_ command: String, _ folder: String) throws {
        let log = FileManager.default.temporaryDirectory.appending(path: "xcrew-why-\(UUID().uuidString).log")
        try "/usr/bin/xcrun xcodebuild -scheme App \(command) build\n".write(to: log, atomically: true, encoding: .utf8)
        #expect(BuildLog.derivedData(ofLogAt: log.path) == folder)
    }

    @Test func aFolderWithAQuoteIsQuotedForTheShell() {
        #expect(CorruptModuleCache.fix(derivedData: "/Users/dev/Bob's DD") == #"Remove the cached modules, then build again: rm -rf '/Users/dev/Bob'\''s DD/ModuleCache.noindex' '/Users/dev/Bob'\''s DD/SDKExplicitPrecompiledModules'"#)
    }

    // MARK: The code's own errors, in the same words

    /// A compile error at a line of the project, such as an `#error` quoting the words, is the code's.
    @Test(arguments: [
        "malformed or corrupted precompiled file: 'from a string'",
        "file 'Fixtures/Stub.pcm' is not a valid module file: a test fixture",
        "Unable to find a device matching the provided destination specifier:",
    ])
    func anErrorAtALineOfTheProjectIsTheCodes(_ message: String) async {
        let project = Project.temporary(containing: ["App/ContentView.swift"])
        let text = """

            🔨 Build

            Errors (1):

              ✗ \(message)
                \(project.root.path)/App/ContentView.swift:3
                { platform:iOS Simulator, OS:latest, name:iPhone 1 }

            ❌ Build failed. (⏱️ 1.1s)
            """
        #expect(await note(text, project: project) == nil)
    }

    /// Errors that follow a corrupt module, and that a missing dependency also gives, say nothing alone.
    @Test(arguments: [
        "missing required module 'SwiftShims'",
        "Unable to resolve module dependency: 'NoSuchModule' (in target 'App' from project 'App')",
        "could not build module 'Dispatch'",
    ])
    func aModuleThatIsMissingIsNotACorruptCache(_ message: String) async {
        let text = "\n🔨 Build\n\nErrors (1):\n\n  ✗ \(message)\n\n❌ Build failed. (⏱️ 1.7s)\n"
        #expect(await note(text) == nil)
    }

    /// A failing test's message is the test author's words.
    @Test func aFailingTestsMessageIsTheCodes() async {
        let text = """

            🧪 Test

            Test Failures:

              ✗ AppTests / testCache(): failed - malformed or corrupted precompiled file: 'expected'
                /testbed/App/AppTests/CacheTests.swift:12

            ❌ Test failed. (⏱️ 3.0s)
            """
        #expect(await note(text) == nil)
    }

    /// An ordinary compile error explains nothing.
    @Test func aCompileErrorExplainsNothing() async {
        let text = "\n🔨 Build\n\nErrors (1):\n\n  ✗ cannot convert value of type 'String' to specified type 'Int'\n    /Users/dev/App/App/ContentView.swift:13\n\n❌ Build failed. (⏱️ 3.2s)\n"
        #expect(await note(text) == nil)
    }

    // MARK: In the report

    /// A failed build's report carries the note for Claude, first, and apart for the failures pane to open with.
    @Test func aFailedBuildsReportCarriesTheNote() async {
        let runner = FakeRunner.simulators(["iPhone 17"])
        let project = Project.temporary()
        let report = await Report.make(kind: .build, output: ToolOutput(text: Self.missingSimulator, server: .mobileBuildMCP, isError: true), home: project.root.path, runner: runner, project: project)
        #expect(report.cause?.hasPrefix("xcrew: this build failed because of the Mac, not the code: no simulator here is named iPhone 1") == true)
        #expect(report.notes.first == report.cause)
    }

    /// A passing build is never explained.
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aPassingBuildLooksAtNothing() async throws {
        let runner = FakeRunner()
        let report = await Report.make(kind: .build, output: Raw.output("build_sim"), home: "/Users/dev", runner: runner, project: .temporary())
        #expect(!report.notes.contains { $0.contains("because of the Mac") })
        #expect(report.cause == nil)
    }
}

/// A build that found its build database locked: an xcodebuild a stopped call left running still holds the DerivedData.
/// The error is Xcode's own wording; the field report saw it after a MobileBuildMCP call was stopped mid-build.
@Suite struct LockedBuildDatabaseTests {
    static let derivedData = "/Users/dev/Library/Developer/Xcode/DerivedData/App-abcdef"
    static let locked = """

        🔨 Build

        Errors (1):

          ✗ unable to attach DB: error: accessing build database "\(derivedData)/Build/Intermediates.noindex/XCBuildData/build.db": database is locked Possibly there are two concurrent builds running in the same filesystem location.

        ❌ Build failed. (⏱️ 1.1s)
        """

    static let database = "\(derivedData)/Build/Intermediates.noindex/XCBuildData/build.db"
    static let because = "xcrew: this build failed because of the Mac, not the code: "
    static let free = because + "its build database is locked (\"database is locked\") by another build, and no process holds it now. Build again."

    /// One process, as the two `ps` calls and `lsof` see it.
    struct Running {
        var id: Int32 = 4242
        var etime = "12:05"
        var path = "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"
        var arguments = "build -workspace App.xcworkspace -scheme App -destination platform=iOS Simulator,name=iPhone 17 -derivedDataPath \(LockedBuildDatabaseTests.derivedData)"
        var holds = false
        var named = true
    }

    /// The note `why` gives for `text`, with these processes running; `ps` and `lsof` failing when `listed` is false.
    static func note(_ running: [Running], text: String = locked, listed: Bool = true) async -> String? {
        let ps = "    1     0 3-00:00:00 /sbin/launchd\n" + running.map { " \($0.id)     1 \($0.etime) \($0.path) \($0.arguments)\n" }.joined()
        let comm = "    1 /sbin/launchd\n" + running.filter(\.named).map { " \($0.id) \($0.path)\n" }.joined()
        let holders = running.filter(\.holds).map { "\($0.id)\n" }.joined()
        let database = text.firstMatch(of: #/build database "([^"]+)"/#).map { String($0.1) } ?? Self.database
        let runner = FakeRunner(responses: listed ? [
            "ps -axo pid=,ppid=,etime=,command=": .init(status: 0, stdout: ps),
            "ps -axo pid=,comm=": .init(status: 0, stdout: comm),
            "lsof -t \(database)": holders.isEmpty ? .init(status: 1) : .init(status: 0, stdout: holders),
        ] : [:])
        return await Why.note(for: ToolOutput(text: text, server: .mobileBuildMCP, isError: true), home: "/home", project: .temporary(), runner: runner)
    }

    @Test func anXcodebuildBuildingIntoItIsNamedWithHowToStopIt() async {
        #expect(await Self.note([Running()]) == Self.because + "an xcodebuild holds its build database (\"database is locked\"): pid 4242, for platform=iOS Simulator,name=iPhone 17, running 12 min. A call stopped partway leaves its xcodebuild running; stopping it frees the database: kill 4242")
    }

    /// Of the processes holding it, an xcodebuild is the one named; Xcode's build service is never the one to stop.
    @Test func anXcodebuildIsNamedBeforeTheBuildService() async {
        let service = Running(id: 5151, etime: "00:40", path: "/Applications/Xcode.app/Contents/SharedFrameworks/SWBBuildService", arguments: "", holds: true)
        #expect(await Self.note([service, Running(holds: true)])?.hasSuffix("kill 4242") == true)
        #expect(await Self.note([service]) == Self.because + "SWBBuildService holds its build database (\"database is locked\"): pid 5151, running 40 s, a build still going, in Xcode or another session. The database is free once it ends.")
    }

    @Test func withNoneRunningNothingHoldsItNow() async {
        #expect(await Self.note([]) == Self.free)
    }

    /// When the processes can't be listed, nothing is said about whether one holds it.
    @Test func withoutTheProcessListItSaysItCouldntTell() async {
        #expect(await Self.note([], listed: false) == Self.because + "its build database is locked (\"database is locked\") by another build; xcrew couldn't list the processes to say which.")
    }

    /// An xcodebuild building into other DerivedData, one whose name only starts the same included, doesn't hold this one.
    @Test(arguments: ["/Users/dev/Library/Developer/Xcode/DerivedData/Other-123456", "\(Self.derivedData)-2"])
    func anXcodebuildElsewhereIsntTheOne(_ building: String) async {
        #expect(await Self.note([Running(arguments: "build -derivedDataPath \(building)")]) == Self.free)
    }

    /// The same folder spelled with a trailing slash, and an xcodebuild ps gave no program name for, are still found.
    @Test func theSameFolderSpelledAnotherWayIsFound() async {
        #expect(await Self.note([Running(arguments: "build -derivedDataPath \(Self.derivedData)/", named: false)])?.hasSuffix("kill 4242") == true)
    }

    /// A build database outside DerivedData's usual layout is still read, and its holder named.
    @Test func aBuildDatabaseElsewhereIsReadToo() async {
        let text = Self.locked.replacingOccurrences(of: Self.database, with: "/Users/dev/App/build/XCBuildData/build.db")
        #expect(await Self.note([Running(holds: true)], text: text)?.hasSuffix("kill 4242") == true)
    }

    /// A test's own SQLite error says the same words: it's the code's, and nothing is said.
    @Test func aTestsDatabaseErrorIsTheCodes() async {
        let text = "\n🧪 Test\n\nTest Failures (1):\n\n  ✗ StoreTests / testWrites: SQLite error 5: database is locked\n\n❌ 1 test failed, 0 passed, 0 skipped (⏱️ 1.0s)"
        #expect(await Self.note([Running()], text: text) == nil)
    }

    /// An xcodebuild running since yesterday reads in days and hours, not thousands of minutes.
    @Test func aLongRunReadsInHoursAndDays() async {
        #expect(await Self.note([Running(etime: "1-02:00:00")])?.contains("running 1 d 2 h") == true)
    }

    /// A destination with a dash in its name is read to the next option.
    @Test func aDestinationWithADashIsReadWhole() async {
        #expect(await Self.note([Running(arguments: "build -destination platform=iOS Simulator,name=Test - iPhone 17 -derivedDataPath \(Self.derivedData)")])?.contains("for platform=iOS Simulator,name=Test - iPhone 17,") == true)
    }
}
