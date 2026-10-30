import Foundation
import Testing
import XcrewTestSupport

@testable import XcrewCore

/// Xcode's scheme selection as MobileBuildMCP 2.7.1 reads it (docs/findings.md, *Xcode's scheme selection*): its
/// `utils/nskeyedarchiver-parser.js`, `utils/xcode-state-reader.js`, `utils/xcode-process.js` and `server/bootstrap.js`.
@Suite struct XcodeSelectionTests {
    static let captured = Bundle.module.url(forResource: "UserInterfaceState", withExtension: "xcuserstate", subdirectory: "Fixtures/Xcode")!

    /// Captured from Xcode 27.2 on the test bed's `Field.xcworkspace`, with paths and ids replaced.
    @Test func aCapturedStateNamesItsScheme() {
        #expect(XcodeSelection.scheme(inStateAt: Self.captured) == "App")
    }

    @Test func theArchivesShapeNamesItsScheme() {
        #expect(XcodeSelection.scheme(in: FakeXcodeState.archive(scheme: "Feature")) == "Feature")
    }

    /// The parser gives nothing for another archiver, a selection with no name, a name that isn't a string, or bytes
    /// that aren't a property list; it never fails.
    @Test func anythingElseNamesNoScheme() {
        #expect(XcodeSelection.scheme(in: FakeXcodeState.archive(scheme: "App", archiver: "NSArchiver")) == nil)
        #expect(XcodeSelection.scheme(in: FakeXcodeState.archive(scheme: "App", withName: false)) == nil)
        #expect(XcodeSelection.scheme(in: FakeXcodeState.archive(scheme: nil)) == nil)
        #expect(XcodeSelection.scheme(in: Data("not a plist".utf8)) == nil)
        #expect(XcodeSelection.scheme(inStateAt: URL(fileURLWithPath: "/nonexistent/UserInterfaceState.xcuserstate")) == nil)
    }

    /// A damaged file reads as nothing: cut short, or a list that holds itself, which would never end.
    @Test func aDamagedStateReadsAsNothing() throws {
        let captured = try Data(contentsOf: Self.captured)
        #expect(XcodeSelection.scheme(in: captured.prefix(captured.count / 2)) == nil)
        // Header, one array holding itself, its offset, and the trailer: one-byte offsets and references, one object.
        let trailer: [UInt8] = [0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10]
        let looped: [UInt8] = Array("bplist00".utf8) + [0xA1, 0x00, 8] + trailer
        #expect(BinaryPropertyList.read(Data(looped)) == nil)
        #expect(BinaryPropertyList.read(BinaryPropertyList.array([.string("a"), .uid(3), .integer(300)]).encoded) == .array([.string("a"), .uid(3), .integer(300)]))
    }

    /// A trailer claiming more objects than fit, or references shared so often the walk would never end, read as
    /// nothing.
    @Test func aHostileStateReadsAsNothing() {
        let trailer: [UInt8] = [0, 0, 0, 0, 0, 0, 8, 1, 0x20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8]
        let overflowing: [UInt8] = Array("bplist00".utf8) + [UInt8](repeating: 0, count: 32) + trailer
        #expect(BinaryPropertyList.read(Data(overflowing)) == nil)
        // Object n is an array holding object n + 1 twice, 40 deep: 2^40 visits without a budget.
        let depth = 40
        var objects: [[UInt8]] = (0..<depth).map { [0xA2, UInt8($0 + 1), UInt8($0 + 1)] }
        objects.append([0x51, 0x61])
        var bytes = Array("bplist00".utf8), offsets: [UInt8] = []
        for object in objects {
            offsets.append(UInt8(bytes.count))
            bytes += object
        }
        let table = bytes.count
        let sizes: [UInt8] = [0, 0, 0, 0, 0, 0, 1, 1]
        let count: [UInt8] = [0, 0, 0, 0, 0, 0, 0, UInt8(objects.count)]
        let top = [UInt8](repeating: 0, count: 8)
        let tableAt: [UInt8] = [0, 0, 0, 0, 0, 0, 0, UInt8(table)]
        bytes += offsets
        bytes += sizes + count + top + tableAt
        #expect(BinaryPropertyList.read(Data(bytes)) == nil)
    }

    /// `findXcodeStateFile`: the configured container's file first, when it's there.
    @Test func theConfiguredContainersStateIsRead() {
        let project = Project.temporary()
        project.write("", to: FakeXcodeState.path(of: "App.xcodeproj"))
        project.write("", to: FakeXcodeState.path(of: "Other.xcworkspace"))
        #expect(XcodeSelection.stateFile(in: project, configured: project.root.appending(path: "App.xcodeproj"), user: "someone")?.path == project.root.appending(path: FakeXcodeState.path(of: "App.xcodeproj")).path)
    }

    /// Without one, the newest among workspaces and projects up to six folders down, never a project's own inner
    /// workspace, and only this user's.
    @Test func otherwiseTheNewestStateBelowTheRootIsRead() throws {
        let project = Project.temporary()
        for container in ["a/App.xcodeproj", "b/c/Modules.xcworkspace", "Old.xcworkspace"] { project.write("", to: FakeXcodeState.path(of: container)) }
        project.write("", to: FakeXcodeState.path(of: "Else.xcworkspace", user: "another"))
        project.write("", to: "1/2/3/4/5/6/Deep.xcworkspace/xcuserdata/someone.xcuserdatad/UserInterfaceState.xcuserstate")
        let dates: [(String, TimeInterval)] = [("a/App.xcodeproj", 100), ("b/c/Modules.xcworkspace", 300), ("Old.xcworkspace", 200)]
        for (container, seconds) in dates {
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: seconds)], ofItemAtPath: project.root.appending(path: FakeXcodeState.path(of: container)).path)
        }
        #expect(XcodeSelection.stateFile(in: project, configured: project.root.appending(path: "Missing.xcodeproj"), user: "someone")?.path == project.root.appending(path: FakeXcodeState.path(of: "b/c/Modules.xcworkspace")).path)
        #expect(XcodeSelection.stateFile(in: project, configured: nil, user: "nobody") == nil)
    }

    /// `isRunningUnderXcode` over the process and those above it.
    @Test func xcodeIsKnownByProgramOrCommand() {
        let ps = """
              10     1 01:00 /Applications/Xcode-27.2.0.app/Contents/MacOS/Xcode
              20    10 01:00 claude
              30    20 01:00 node build/cli.js mcp
              40     1 01:00 /bin/zsh -l
              50    40 01:00 claude
              60     1 01:00 /usr/libexec/agent --for com.apple.dt.Xcode
              70    60 01:00 claude
            """
        let list = ProcessList(ps: ps)
        #expect(list.runsUnderXcode(30))
        #expect(!list.runsUnderXcode(50))
        #expect(list.runsUnderXcode(70))
        // `ps -o comm=` gives the name alone for some processes: that name, as the parser's first field, is Xcode.
        #expect(ProcessList(ps: "  10     1 01:00 /some/where/Xcode --flag\n", comm: "10 Xcode\n").runsUnderXcode(10))
        #expect(!ProcessList(ps: "  10     1 01:00 /some/where/Xcode --flag\n", comm: "10 /some/where/Xcode\n").runsUnderXcode(10))
        #expect(!ProcessList(ps: "  10     1 01:00 /bin/XcodeHelper\n", comm: "10 /bin/XcodeHelper\n").runsUnderXcode(10))
        // Before `args`, `ps` cuts `comm` to 16 characters, so only `args` can name the path past them.
        #expect(!ProcessList(ps: "  10     1 01:00 Xcode\n", comm: "10 /Applications/Xcode 27.app/Contents/MacOS/Xcode\n").runsUnderXcode(10))
    }

    @Test func autoSyncIsOffOnlyWhenTheConfigSaysSo() {
        #expect(ConfigRenderer.disablesXcodeAutoSync(in: "schemaVersion: 1\ndisableXcodeAutoSync: true\n"))
        #expect(!ConfigRenderer.disablesXcodeAutoSync(in: "schemaVersion: 1\ndisableXcodeAutoSync: false\n"))
        #expect(!ConfigRenderer.disablesXcodeAutoSync(in: "schemaVersion: 1\n"))
        #expect(!ConfigRenderer.disablesXcodeAutoSync(in: "sessionDefaults:\n  disableXcodeAutoSync: true\n"))
    }

    /// A named profile stands alone: its own scheme, never the active one's.
    @Test func aNamedProfilesSchemeIsItsOwn() {
        let yaml = "sessionDefaultsProfiles:\n  unit:\n    scheme: AppTests\n  app:\n    scheme: 'App'\n  ui:\n    scheme: null\nactiveSessionDefaultsProfile: unit\n"
        #expect(ConfigRenderer.schemeToBuild(in: yaml, profile: "app") == "App")
        #expect(ConfigRenderer.schemeToBuild(in: yaml, profile: "ui") == nil)
        #expect(ConfigRenderer.schemeToBuild(in: yaml, profile: "gone") == nil)
        #expect(ConfigRenderer.schemeToBuild(in: yaml) == "AppTests")
        // MobileBuildMCP's name for its global defaults, `formatProfileLabel(null)`.
        #expect(ConfigRenderer.schemeToBuild(in: "sessionDefaults:\n  scheme: Global\n" + yaml, profile: "(default)") == "Global")
    }

    static func machine(_ project: Project, underXcode: Bool) -> Machine {
        Machine(environment: [:], home: project.root.appending(path: "home"), runner: FakeRunner.mobileBuildMCP(serving: project, underXcode: underXcode), processID: 40)
    }

    @Test func underXcodeTheSelectionIsReadAndFollowedUnlessTurnedOff() async throws {
        let project = Project.temporary()
        try FakeXcodeState.write(scheme: "Feature", for: "App.xcworkspace", in: project)
        project.write("sessionDefaultsProfiles:\n  unit:\n    workspacePath: ./App.xcworkspace\n    scheme: AppTests\nactiveSessionDefaultsProfile: unit\n", to: ".mobilebuildmcp/config.yaml")
        let read = await XcodeSelection.read(for: project, machine: Self.machine(project, underXcode: true))?.selection
        #expect(read == XcodeSelection(state: project.root.appending(path: FakeXcodeState.path(of: "App.xcworkspace")).standardizedFileURL, scheme: "Feature", follows: true, activeProfile: "unit"))
        project.write("sessionDefaults:\n  workspacePath: ./App.xcworkspace\n", to: ".mobilebuildmcp/config.yaml")
        #expect(await XcodeSelection.read(for: project, machine: Self.machine(project, underXcode: true))?.selection?.activeProfile == "(default)")
        project.write("disableXcodeAutoSync: true\nsessionDefaultsProfiles:\n  unit:\n    workspacePath: ./App.xcworkspace\nactiveSessionDefaultsProfile: unit\n", to: ".mobilebuildmcp/config.yaml")
        #expect(await XcodeSelection.read(for: project, machine: Self.machine(project, underXcode: true))?.selection?.follows == false)
    }

    /// From a terminal, MobileBuildMCP never reads Xcode's selection, whatever Xcode has selected.
    @Test func outsideXcodeNothingIsRead() async throws {
        let project = Project.temporary()
        try FakeXcodeState.write(scheme: "Feature", for: "App.xcworkspace", in: project)
        let read = await XcodeSelection.read(for: project, machine: Self.machine(project, underXcode: false))
        #expect(read?.hostsServer == false && read?.selection == nil)
    }
}
