import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// `xcrew space`: what MobileBuildMCP and Xcode keep on this Mac, from captures of what each tool answered, with the
/// command that would reclaim each part and never a deletion of its own.
@Suite struct SpaceTests {
    static func fixture(_ name: String) -> String {
        try! String(contentsOf: Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/Storage")!, encoding: .utf8)
    }

    /// The capture with `key` for this project's workspace, and each of `renamed`'s fixture keys under its new key.
    static func purgeReport(key: String, renamed: [String: String] = [:]) -> String {
        renamed.reduce(fixture("purgeReportAll").replacingOccurrences(of: "kit-0a1b2c3d4e5f", with: key)) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
    }

    /// Writes a workspace's build log naming `root`'s workspace, so its origin is read from it.
    static func writeLog(home: URL, key: String, root: String) throws {
        let log = home.appending(path: "Library/Developer/MobileBuildMCP/workspaces/\(key)/logs/build_sim_1.log")
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "xcodebuild build -workspace \(root)/Gone.xcworkspace -scheme Gone\n".write(to: log, atomically: true, encoding: .utf8)
    }

    /// `git` in a main checkout at `root` with linked worktrees at `worktrees`.
    static func git(root: String, worktrees: [String] = []) -> [String: CommandResult] {
        let blocks = ["worktree \(root)\nHEAD 0123\nbranch refs/heads/main"] + worktrees.map { "worktree \($0)\nHEAD 0456\nbranch refs/heads/wt" }
        return [
            "git -C \(root) rev-parse --show-prefix": .init(status: 0, stdout: "\n"),
            "git -C \(root) worktree list --porcelain": .init(status: 0, stdout: blocks.joined(separator: "\n\n") + "\n"),
        ]
    }

    /// 2026-11-02 00:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_793_577_600)

    /// In the temporary folder as the file system spells it, `/private` included, as a listing gives its paths back.
    let home = URL(fileURLWithPath: ProjectLayout.canonicalPath(FileManager.default.temporaryDirectory.path)).appending(path: "xcrew-tests-\(UUID().uuidString)")
    /// This project, in a folder named `App`, pinning Xcode 26.4; its workspace key is the one `RunLog` gives its root.
    let project: Project
    var root: String { project.root.path }
    var key: String { RunLog.workspaceKey(root: root) }
    /// A project folder that's gone from a folder that's there: this test's home.
    var goneRoot: String { home.appending(path: "Gone").path }
    var goneKey: String { RunLog.workspaceKey(root: goneRoot) }

    init() {
        let folder = FileManager.default.temporaryDirectory.appending(path: "xcrew-tests-\(UUID().uuidString)/App")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try! "26.4\n".write(to: folder.appending(path: ".xcode-version"), atomically: true, encoding: .utf8)
        project = Project(root: folder)
    }

    func write(_ text: String, to path: String) throws {
        let url = home.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func derivedData(_ name: String, workspace: String) throws {
        try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict><key>WorkspacePath</key><string>\(workspace)</string></dict></plist>\n", to: "Library/Developer/Xcode/DerivedData/\(name)/info.plist")
    }

    /// The captured Mac: this project's workspace (the capture's largest, under this project's key), a workspace whose
    /// project is gone, two whose project isn't known; three runtimes, five devices; three Xcodes; Xcode's DerivedData for
    /// this project and for one that's gone; an archive.
    func report(xcodes: Bool = true) async throws -> SpaceReport {
        let purge = Self.purgeReport(key: key, renamed: ["field-09f4495eb86d": goneKey])
        try Self.writeLog(home: home, key: goneKey, root: goneRoot)
        try FileManager.default.createDirectory(at: project.root.appending(path: "App.xcworkspace"), withIntermediateDirectories: true)
        try derivedData("App-abc", workspace: "\(root)/App.xcworkspace")
        try derivedData("Old-def", workspace: "/work/Old/Old.xcodeproj")
        try write("", to: "Library/Developer/Xcode/Archives/2026-10-30/App.xcarchive/Info.plist")
        let apps = home.appending(path: "Applications")
        FakeXcode.install(in: apps, "Xcode-27.2.app", version: "27.2", build: "27C5")
        FakeXcode.install(in: apps, "Xcode-26.4.app", version: "26.4", build: "17E192")
        FakeXcode.install(in: apps, "Xcode-26.0.app", version: "26.0", build: "17A100")
        var responses: [String: CommandResult] = Self.git(root: root).merging([
            "mobilebuildmcp purge --report --scope all --json": .init(status: 0, stdout: purge),
            "xcrun simctl runtime list -j": .init(status: 0, stdout: Self.fixture("simctlRuntimeList")),
            "xcrun simctl list devices -j": .init(status: 0, stdout: Self.fixture("simctlDevices")),
            "xcode-select -p": .init(status: 0, stdout: "\(apps.path)/Xcode-27.2.app/Contents/Developer\n"),
        ]) { $1 }
        for (app, bytes) in [("Xcode-27.2.app", "3628081152"), ("Xcode-26.4.app", "3400000000"), ("Xcode-26.0.app", "3100000000")] {
            responses["mdls -raw -name kMDItemPhysicalSize \(apps.path)/\(app)"] = .init(status: 0, stdout: bytes)
        }
        let dd = home.appending(path: "Library/Developer/Xcode/DerivedData").path
        responses["du -sk \(dd)/App-abc"] = .init(status: 0, stdout: "1200\t\(dd)/App-abc\n")
        responses["du -sk \(dd)/Old-def"] = .init(status: 0, stdout: "3000\t\(dd)/Old-def\n")
        let archives = home.appending(path: "Library/Developer/Xcode/Archives").path
        responses["du -sk \(archives)"] = .init(status: 0, stdout: "52000\t\(archives)\n")
        let machine = Machine(environment: [:], home: home, runner: FakeRunner(installed: xcodes ? ["xcodes"] : [], responses: responses), applications: apps)
        return await Space.report(project: project, machine: machine, now: Self.now)
    }

    @Test func thisProjectsWorkspaceIsNamedWithTheCommandThatWouldReclaimIt() async throws {
        let text = try await report().text
        #expect(text.contains("  App, \(root): 81.5 MB, DerivedData 77.9 MB, newest 2 d ago\n      mobilebuildmcp purge --dry-run --scope workspace --workspace-key \(key) --classes derivedData,logs,resultBundles,stateTransients,testProducts\n"), "\(text)")
        #expect(text.contains("  Each `--dry-run` lists what it would delete; with `--delete` in its place and `--confirm delete-mobilebuildmcp-storage`, it deletes.\n"), "\(text)")
    }

    /// Only a root its log names and its key confirms is said to be gone; the rest are counted, with what age would take.
    @Test func aGoneProjectsWorkspaceIsNamedAndTheUnknownAreCounted() async throws {
        let text = try await report().text
        #expect(text.contains("  \(goneKey): 305.5 KB; its project, \(goneRoot), is gone\n      mobilebuildmcp purge --dry-run --scope workspace --workspace-key \(goneKey) --classes logs,resultBundles,stateTransients,testProducts\n"), "\(text)")
        #expect(text.contains("  2 workspaces whose project isn't known: 3.3 MB; `mobilebuildmcp purge --report --json` lists each\n"), "\(text)")
        #expect(!text.contains("--scope all"), "a command over every workspace would reach this project's too")
    }

    /// Xcode's DerivedData records its workspace, so one whose workspace is gone is named; nothing offers to delete it.
    /// A root whose folder above is missing too, as on a volume not mounted, may be there yet: it's not said to be gone.
    @Test func aRootOnAMissingVolumeIsntGone() async throws {
        let away = "/Volumes/xcrew-tests-\(UUID().uuidString)/App"
        let awayKey = RunLog.workspaceKey(root: away)
        let report = try #require(StorageReport(json: Data(Self.purgeReport(key: key, renamed: ["field-09f4495eb86d": awayKey]).utf8)))
        try Self.writeLog(home: home, key: awayKey, root: away)
        let origins = await ProjectWorkspaces.origins(of: report, live: [], home: home)
        #expect(origins[awayKey] == .unknown)
    }

    @Test func xcodesDerivedDataIsSplitByItsWorkspace() async throws {
        let text = try await report().text
        #expect(text.contains("  App-abc, for this project: 1.2 MB\n"), "\(text)")
        #expect(text.contains("  Old-def: 3.1 MB; its workspace, /work/Old/Old.xcodeproj, is gone\n"), "\(text)")
        #expect(!text.contains("rm -"))
    }

    @Test func eachRuntimeIsSizedWithItsLastUseAsSimctlRecordsIt() async throws {
        let text = try await report().text
        #expect(text.contains("  iOS 27.2 (24B8117): 8.3 GB, last used 2 d ago\n"), "\(text)")
        #expect(text.contains("  iOS 27.1 (24A94425): 7.9 GB, no last use recorded\n"), "\(text)")
        #expect(text.contains("      xcrun simctl runtime delete --notUsedSinceDays 30 --dry-run\n"), "\(text)")
    }

    @Test func devicesAreTotalledAndTheUnavailableCounted() async throws {
        let text = try await report().text
        #expect(text.contains("  5 devices: 2.4 GB of data, 1 unavailable\n      xcrun simctl delete unavailable\n"), "\(text)")
    }

    /// The selected and the pinned Xcode are never offered for uninstalling, and nothing is offered without `xcodes`.
    @Test func onlyAnXcodeNeitherSelectedNorPinnedIsOffered() async throws {
        let text = try await report().text
        #expect(text.contains("  Xcode 27.2, selected: 3.6 GB\n  Xcode 26.4, pinned: 3.4 GB\n  Xcode 26.0: 3.1 GB\n      xcodes uninstall 26.0\n"), "\(text)")
        #expect(!(try await report(xcodes: false).text.contains("xcodes uninstall")))
    }

    /// `xcodes uninstall` names a version, so an Xcode whose version another install shares isn't offered: it could
    /// reach the selected or the pinned one.
    @Test func anXcodeSharingItsVersionIsntOffered() async throws {
        FakeXcode.install(in: home.appending(path: "Applications"), "Xcode-26.0-copy.app", version: "26.0", build: "17A100")
        let text = try await report().text
        #expect(!text.contains("xcodes uninstall"), "\(text)")
    }

    /// A removed worktree's DerivedData is gone though its path sits in the project; one at the project's own root is
    /// the project's.
    @Test func derivedDataOfARemovedWorktreeIsGoneAndOfTheRootIsTheProjects() async throws {
        try derivedData("Fix-ghi", workspace: "\(root)/.claude/worktrees/fix/App.xcworkspace")
        try derivedData("Root-jkl", workspace: root)
        let text = try await report().text
        #expect(text.contains("  Fix-ghi: not measured; its workspace, \(root)/.claude/worktrees/fix/App.xcworkspace, is gone\n"), "\(text)")
        #expect(text.contains("  Root-jkl, for this project: not measured\n"), "\(text)")
    }

    /// Xcode's DerivedData kept beside each workspace, a relative location, can't be listed from one folder: said so.
    @Test func aRelativeDerivedDataLocationIsSaidNotRead() async {
        let runner = FakeRunner(responses: ["defaults read com.apple.dt.Xcode IDECustomDerivedDataLocation": .init(status: 0, stdout: "DerivedData\n")])
        let machine = Machine(environment: [:], home: home, runner: runner)
        let part = await Space.xcodeDerivedData(in: await Space.derivedDataFolder(machine: machine), live: Task { [] }, machine: machine)
        #expect(part?.lines.map(\.text) == ["not read: Xcode keeps DerivedData in each workspace's folder (`DerivedData`)"])
    }

    /// Archives are the person's builds: sized, never offered.
    @Test func archivesAreSizedAndNeverOffered() async throws {
        let text = try await report().text
        #expect(text.contains("  Archives: 53.2 MB\n"), "\(text)")
        #expect(!text.contains("Archives: 53.2 MB\n      "))
    }

    /// A tool that doesn't answer is said not to have been read; the other parts stand.
    @Test func aToolThatDoesntAnswerIsSaidSo() async throws {
        let machine = Machine(environment: [:], home: home, runner: FakeRunner(), applications: home)
        let text = await Space.report(project: project, machine: machine, now: Self.now).text
        #expect(text.contains("MobileBuildMCP\n  not read: `mobilebuildmcp purge --report` didn't answer\n"), "\(text)")
        #expect(text.contains("Simulator runtimes\n  not read: `xcrun simctl runtime list` didn't answer\n"), "\(text)")
    }
}
