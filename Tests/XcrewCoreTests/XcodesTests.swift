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
        bundle(in: folder, "Xcode-26.4.app", identifier: "com.apple.dt.Xcode", version: "26.4", build: "17E192")
        bundle(in: folder, "Xcode-27.2.0-Beta.3.app", identifier: "com.apple.dt.Xcode", version: "27.2", build: "27B5038j")
        bundle(in: folder, "Xcodes.app", identifier: "com.xcodesorg.xcodesapp", version: "4.1.1", build: nil)
        return folder
    }

    static func bundle(in folder: URL, _ name: String, identifier: String, version: String, build: String?) {
        FakeXcode.install(in: folder, name, identifier: identifier, version: version, build: build)
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
        Self.bundle(in: elsewhere, "Xcode-25.3.app", identifier: "com.apple.dt.Xcode", version: "25.3", build: "16E140")
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

    @Test func thePinIsTheFileBesideTheProjectOrItsContainer() {
        let root = Project.temporary(containing: ["ios/App.xcworkspace"])
        #expect(Xcodes.pin(of: root) == nil)
        root.write("26.4\n", to: "ios/.xcode-version")
        #expect(Xcodes.pin(of: root)?.version == "26.4")
        #expect(Xcodes.pin(of: root)?.file == "ios/.xcode-version")
    }

    /// The selected Xcode is the one `DEVELOPER_DIR` names, else `xcode-select`'s, as the app holding the developer folder.
    @Test func theSelectedXcodeIsTheAppAroundTheDeveloperFolder() async {
        let apps = Self.applications()
        let runner = FakeRunner(responses: ["xcode-select -p": .init(status: 0, stdout: "\(apps.path)/Xcode-26.4.app/Contents/Developer\n")])
        #expect(await Xcodes.selected(on: machine(apps, runner: runner))?.version == "26.4")
        let overridden = machine(apps, runner: runner, environment: ["DEVELOPER_DIR": "\(apps.path)/Xcode-27.2.0-Beta.3.app/Contents/Developer"])
        #expect(await Xcodes.selected(on: overridden)?.version == "27.2")
    }

    /// GitHub Actions names an Xcode three ways: setup-xcode's input, `xcode-select -s` and `DEVELOPER_DIR`. A version
    /// that picks the newest names none.
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
        let named = Xcodes.ci(of: project)
        #expect(named.map(\.line) == [5, 9, 10, 13])
        #expect(named.map(\.version) == ["26.3", "26.4", "26.4.1", nil])
        #expect(named.allSatisfy { $0.file == ".github/workflows/ci.yml" })
    }

    @Test func theRunningXcodeIsTheAppAroundItsProcess() async {
        let apps = Self.applications()
        let runner = FakeRunner(responses: ["ps -axo comm=": .init(status: 0, stdout: "/usr/sbin/cfprefsd\n\(apps.path)/Xcode-27.2.0-Beta.3.app/Contents/MacOS/Xcode\n/System/Applications/Mail.app/Contents/MacOS/Mail\n")])
        #expect(await Xcodes.running(on: machine(apps, runner: runner)).map(\.version) == ["27.2"])
    }
}
