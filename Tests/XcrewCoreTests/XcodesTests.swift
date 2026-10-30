import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// A Mac's Xcodes, the project's pin, CI's, and the one running: which Xcode a session's tools build with.
@Suite struct XcodesTests {
    static let spotlight = "mdfind kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'"

    /// An applications folder holding Xcode 26.4, Xcode 27.2 beta 3 and the Xcodes installer, whose name also starts with
    /// "Xcode".
    static func applications() -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "xcrew-apps-\(UUID().uuidString)")
        FakeXcode.installBoth(in: folder)
        FakeXcode.install(in: folder, "Xcodes.app", identifier: "com.xcodesorg.xcodesapp", version: "4.1.1", build: nil)
        return folder
    }

    func machine(_ applications: URL, runner: FakeRunner = FakeRunner(), environment: [String: String] = [:]) -> Machine {
        Machine(environment: environment, home: applications.deletingLastPathComponent(), runner: runner, applications: applications)
    }

    @Test func theInstalledXcodesAreTheBundlesThatAreXcode() async {
        let apps = Self.applications()
        let installed = await Xcodes.installed(on: machine(apps))
        #expect(installed.map(\.version) == ["27.2", "26.4"])
        #expect(installed.map(\.build) == ["27B5038j", "17E192"])
        #expect(installed.map { URL(fileURLWithPath: $0.path).lastPathComponent } == ["Xcode-27.2.0-Beta.3.app", "Xcode-26.4.app"])
    }

    /// Spotlight finds an Xcode kept outside the applications folder.
    @Test func spotlightFindsAnXcodeKeptElsewhere() async {
        let apps = Self.applications()
        let elsewhere = apps.deletingLastPathComponent().appending(path: "elsewhere-\(UUID().uuidString)")
        FakeXcode.install(in: elsewhere, "Xcode-25.3.app", version: "25.3", build: "16E140")
        let runner = FakeRunner(responses: [Self.spotlight: .init(status: 0, stdout: "\(elsewhere.path)/Xcode-25.3.app\n")])
        #expect(await Xcodes.installed(on: machine(apps, runner: runner)).map(\.version) == ["27.2", "26.4", "25.3"])
    }

    /// `.xcode-version` holds one version, with or without a trailing newline; a beta's `b<n>` and trailing zeros don't
    /// change which Xcode it names.
    @Test func aPinNamesTheInstallOfItsVersion() async {
        let installed = await Xcodes.installed(on: machine(Self.applications()))
        #expect(Xcodes.matching("26.4\n", in: installed)?.version == "26.4")
        #expect(Xcodes.matching("26.4.0", in: installed)?.version == "26.4")
        #expect(Xcodes.matching("27.2b3", in: installed)?.version == "27.2")
        #expect(Xcodes.matching("25.0", in: installed) == nil)
    }

    /// A beta and a release of one version both match a pin by its number. A pin without a beta's `b<n>` takes the
    /// release, one with it the beta, the same way wherever the pin is looked up.
    @Test func aPinTellsABetaFromARelease() async {
        let apps = Self.applications()
        FakeXcode.install(in: apps, "Xcode-27.2.app", version: "27.2", build: "27C100")
        let installed = await Xcodes.installed(on: machine(apps))
        let name = { (install: XcodeInstall?) in install.map { URL(fileURLWithPath: $0.path).lastPathComponent } }
        #expect(name(Xcodes.matching("27.2", in: installed)) == "Xcode-27.2.app")
        #expect(name(Xcodes.matching("27.2b3", in: installed)) == "Xcode-27.2.0-Beta.3.app")
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.write("27.2\n", to: ".xcode-version")
        guard case let .installed(pinned) = await Xcodes.pinned(in: project, on: machine(apps)) else { Issue.record("no install for 27.2"); return }
        #expect(name(pinned) == "Xcode-27.2.app")
    }

    /// A version in a YAML comment is an old setup's, not CI's.
    @Test func aCommentedLineNamesNoXcode() {
        let project = Project.temporary()
        project.write("""
            steps:
              # - run: sudo xcode-select -s /Applications/Xcode_15.4.app
              - uses: maxim-lobanov/setup-xcode@v1
                with:
                  # xcode-version: '15.4'
                  xcode-version: '26.4' # the team's
            """, to: ".github/workflows/ci.yml")
        #expect(CIXcodes.named(in: project).map(\.version) == ["26.4"])
    }

    @Test func thePinIsTheFileBesideTheProjectOrItsContainer() {
        let root = Project.temporary(containing: ["ios/App.xcworkspace"])
        #expect(root.xcodePin == nil)
        root.write("26.4\n", to: "ios/.xcode-version")
        #expect(root.xcodePin?.version == "26.4")
        #expect(root.xcodePin?.file == "ios/.xcode-version")
    }

    /// The selected Xcode is the one `DEVELOPER_DIR` names, else `xcode-select`'s, as the app holding the developer folder.
    @Test func theSelectedXcodeIsTheAppAroundTheDeveloperFolder() async {
        let apps = Self.applications()
        let runner = FakeRunner(responses: ["xcode-select -p": .init(status: 0, stdout: "\(apps.path)/Xcode-26.4.app/Contents/Developer\n")])
        #expect(await Xcodes.selected(on: machine(apps, runner: runner))?.version == "26.4")
        let overridden = machine(apps, runner: runner, environment: ["DEVELOPER_DIR": "\(apps.path)/Xcode-27.2.0-Beta.3.app/Contents/Developer"])
        #expect(await Xcodes.selected(on: overridden)?.version == "27.2")
    }

    /// GitHub Actions names an Xcode three ways: setup-xcode's input, `xcode-select -s` and `DEVELOPER_DIR`. One that
    /// picks the newest, `latest-stable`, names no version to compare.
    @Test func ciNamesItsXcodeInAWorkflow() {
        let project = Project.temporary()
        project.write("""
            jobs:
              test:
                runs-on: macos-26
                env:
                  DEVELOPER_DIR: /Applications/Xcode_26.3.app/Contents/Developer
                steps:
                  - uses: maxim-lobanov/setup-xcode@v1
                    with:
                      xcode-version: '26.4'
                  - run: sudo xcode-select -s /Applications/Xcode_26.4.1.app
                  - uses: maxim-lobanov/setup-xcode@v1
                    with:
                      xcode-version: latest-stable
            """, to: ".github/workflows/ci.yml")
        let named = CIXcodes.named(in: project)
        #expect(named.map(\.line) == [5, 9, 10])
        #expect(named.map(\.version) == ["26.3", "26.4", "26.4.1"])
        #expect(named.allSatisfy { $0.file == ".github/workflows/ci.yml" })
    }

    @Test func theRunningXcodeIsTheAppAroundItsProcess() async {
        let apps = Self.applications()
        let runner = FakeRunner(responses: FakeSession.responses(serving: nil, programs: [101: "/usr/sbin/cfprefsd", 202: "\(apps.path)/Xcode-27.2.0-Beta.3.app/Contents/MacOS/Xcode", 303: "/System/Applications/Mail.app/Contents/MacOS/Mail"]))
        #expect(Xcodes.running(in: await ProcessList.load(using: runner)).map(\.version) == ["27.2"])
    }
}
