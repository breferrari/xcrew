import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// What the doctor said ahead of time about which Xcode builds, said instead on the failed MobileBuildMCP build or test it
/// can explain: one whose errors another SDK or toolchain gives. Each fact only when it holds, and never on a pass.
@Suite struct XcodeFailureNotesTests {
    let fixture = XcodeChecksTests()
    static let applied = "applied APPS/Xcode-26.4.app/Contents/Developer\n"

    func notes(_ context: CheckContext, text: String = XcodeChecksTests.toolchainFailure, isError: Bool = true) async -> [String] {
        await Report.make(kind: .build, output: ToolOutput(text: text, server: .mobileBuildMCP, isError: isError), home: context.machine.home.path, runner: context.runner, project: context.project, machine: context.machine).notes
    }

    /// CI on another Xcode than the pinned one: that alone, no other fact of the doctor's.
    @Test func ciOnAnotherXcodeIsTheOnlyNoteWhenItAloneHolds() async {
        let context = fixture.context(pin: "26.4\n", workflow: XcodeChecksTests.ciOn26_3, launch: Self.applied)
        #expect(await notes(context) == ["xcrew: CI uses Xcode 26.3 (.github/workflows/ci.yml:6), but this project pins Xcode 26.4, so a different SDK from CI's may be the cause: move CI to 26.4, or pin 26.3 in .xcode-version"])
    }

    /// Without a pin, with several Xcodes installed, CI's is suggested as the pin, in place of the CI note.
    @Test func withoutAPinCIsXcodeIsSuggestedAsThePin() async {
        let context = fixture.context(workflow: XcodeChecksTests.ciOn26_3)
        #expect(await notes(context) == ["xcrew: several Xcodes are installed and CI uses Xcode 26.3 (.github/workflows/ci.yml:6), but nothing pins one, so builds use Xcode 27.2, and a different SDK from CI's may be the cause: pin CI's with echo 26.3 > .xcode-version"])
    }

    /// The Xcode MCP's open Xcode other than the one building: two toolchains in one session.
    @Test func anOpenXcodeOtherThanTheBuildsOneIsTheOnlyNoteWhenItAloneHolds() async throws {
        let context = fixture.context(pin: "26.4\n", running: "Xcode-27.2.0-Beta.3.app", launch: Self.applied)
        let said = await notes(context)
        #expect(said.count == 1, "\(said)")
        let note = try #require(said.first)
        #expect(note.hasPrefix("xcrew: the Xcode MCP works through the open Xcode 27.2, but MobileBuildMCP builds with Xcode 26.4, so their builds and errors can disagree: quit Xcode 27.2 and open "), "\(note)")
        #expect(note.hasSuffix("/Xcode-26.4.app"), "\(note)")
    }

    /// With none of them holding, a toolchain failure gets none of them.
    @Test func noFactHoldsNoNote() async {
        #expect(await notes(fixture.context(pin: "26.4\n", launch: Self.applied)) == [])
    }

    /// A failure of the code itself, and a pass, say nothing of which Xcode builds, however much differs.
    @Test func aFailureOfTheCodeOrAPassSaysNothing() async {
        let context = fixture.context(workflow: XcodeChecksTests.ciOn26_3, running: "Xcode-26.4.app")
        #expect(await notes(context, text: XcodeChecksTests.buildFailure("cannot find 'Greeting' in scope")) == [])
        #expect(await notes(context, text: "\n🔨 Build\n\n✅ Build succeeded. (⏱️ 3.2s)", isError: false) == [])
    }

    /// The doctor keeps what xcrew needs to run; these are said on the failure they explain.
    @Test func theDoctorNoLongerChecksThem() async {
        let ids = Doctor.checks.map(\.id)
        #expect(!ids.contains("xcode/open"))
        #expect(!ids.contains("xcode/ci"))
        #expect(!ids.contains("mobilebuildmcp/no-xcodebuild-left"))
        #expect(await XcodePinCheck().run(fixture.context(workflow: XcodeChecksTests.ciOn26_3)) == .pass("no pin"))
    }
}
