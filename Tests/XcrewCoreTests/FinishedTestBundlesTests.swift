import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// The test products a MobileBuildMCP test run made for itself and has finished with, which nothing reads again
/// (docs/findings.md, *Disk space*), dropped from this checkout's workspace alone.
@Suite struct FinishedTestBundlesTests {
    let context = CheckContext.fake()
    var home: URL { context.machine.home }
    var project: Project { context.project }

    /// This checkout's `test-products` folder, as MobileBuildMCP 2.7.1 lays it out.
    func folder(root: String? = nil) -> URL {
        home.appending(path: "Library/Developer/MobileBuildMCP/workspaces/\(RunLog.workspaceKey(root: root ?? project.root.path))/test-products")
    }

    /// A bundle named `name` in `folder`, with the marker MobileBuildMCP writes once its run is done when `finished`,
    /// dated `finishedAt` when given.
    func bundle(_ name: String, in folder: URL, finished: Bool, finishedAt: Date? = nil) throws {
        try FileManager.default.createDirectory(at: folder.appending(path: name).appending(path: "Binaries"), withIntermediateDirectories: true)
        guard finished else { return }
        let marker = folder.appending(path: name + ".mobilebuildmcp-completed")
        try Data().write(to: marker)
        if let finishedAt { try FileManager.default.setAttributes([.modificationDate: finishedAt], ofItemAtPath: marker.path) }
    }

    /// Two runs that overlapped: the one that started first finished last, and its result named its bundle last.
    @Test func theBundleKeptIsTheOneWhoseRunFinishedLast() async throws {
        let folder = folder()
        let finishedLast = "test_sim_2026-11-18T09-00-00-000Z_pid4242_0a1b2c3d.xctestproducts"
        let startedLast = "test_macos_2026-11-18T09-05-00-000Z_pid4243_0a1b2c3e.xctestproducts"
        try bundle(finishedLast, in: folder, finished: true, finishedAt: Date(timeIntervalSince1970: 1_794_996_000))
        try bundle(startedLast, in: folder, finished: true, finishedAt: Date(timeIntervalSince1970: 1_794_995_400))

        #expect(await drop() == 1)
        #expect(names(in: folder) == [finishedLast, finishedLast + ".mobilebuildmcp-completed"])
    }

    /// Drops on a Mac whose running processes have `running` as their command lines, or whose `ps` fails when nil.
    func drop(running: [String]? = []) async -> Int {
        var runner = FakeRunner()
        if let running {
            let lines = running.enumerated().map { "  \($0.offset + 100)     1 00:10 \($0.element)\n" }.joined()
            runner.responses["ps -axo pid=,ppid=,etime=,command="] = .init(status: 0, stdout: lines)
        }
        return await FinishedTestBundles.drop(project: project, machine: CheckContext.fake(runner, project: project).machine)
    }

    /// A run again from a kept bundle doesn't mark it: its own run's marker is still there. A process naming the bundle
    /// is what shows it's in use.
    @Test func aBundleARunningProcessNamesStays() async throws {
        let folder = folder()
        let rerun = "test_sim_2026-11-18T09-00-00-000Z_pid4242_0a1b2c3d.xctestproducts"
        let newest = "test_sim_2026-11-18T10-00-00-000Z_pid4243_0a1b2c3e.xctestproducts"
        try bundle(rerun, in: folder, finished: true, finishedAt: Date(timeIntervalSince1970: 1_794_994_000))
        try bundle(newest, in: folder, finished: true, finishedAt: Date(timeIntervalSince1970: 1_794_996_000))

        let running = ["/usr/bin/xcodebuild test-without-building -testProductsPath \(folder.path)/\(rerun) -destination id=ABC"]
        #expect(await drop(running: running) == 0)
        #expect(names(in: folder).contains(rerun))
    }

    @Test func whenTheRunningProcessesCantBeReadNothingGoes() async throws {
        let folder = folder()
        try bundle("test_sim_2026-11-18T09-00-00-000Z_pid4242_0a1b2c3d.xctestproducts", in: folder, finished: true, finishedAt: Date(timeIntervalSince1970: 1_794_994_000))
        try bundle("test_sim_2026-11-18T10-00-00-000Z_pid4243_0a1b2c3e.xctestproducts", in: folder, finished: true, finishedAt: Date(timeIntervalSince1970: 1_794_996_000))

        #expect(await drop(running: nil) == 0)
        #expect(names(in: folder).count == 4)
    }

    func names(in folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    /// The newest stays: its result named it, so a later call may run from it without building.
    @Test func everyFinishedTestRunBundleButTheNewestGoesWithItsMarker() async throws {
        let folder = folder()
        let newest = "test_sim_2026-11-18T10-00-00-000Z_pid4244_0a1b2c3f.xctestproducts"
        try bundle("test_sim_2026-11-18T09-00-00-000Z_pid4242_0a1b2c3d.xctestproducts", in: folder, finished: true, finishedAt: Date(timeIntervalSince1970: 1_794_994_000))
        try bundle(newest, in: folder, finished: true, finishedAt: Date(timeIntervalSince1970: 1_794_996_000))
        try bundle("test_macos_2026-11-18T09-30-00-000Z_pid4243_0a1b2c3e.xctestproducts", in: folder, finished: true, finishedAt: Date(timeIntervalSince1970: 1_794_995_000))

        let dropped = await drop()

        #expect(dropped == 2)
        #expect(names(in: folder) == [newest, newest + ".mobilebuildmcp-completed"])
    }

    @Test func aLoneFinishedBundleStays() async throws {
        let folder = folder()
        try bundle("test_sim_2026-11-18T09-00-00-000Z_pid4242_0a1b2c3d.xctestproducts", in: folder, finished: true)

        #expect(await drop() == 0)
        #expect(names(in: folder).count == 2)
    }

    @Test func aRunStillGoingABuildForTestingsAndAnotherToolsBundleStay() async throws {
        let folder = folder()
        let going = "test_sim_2026-11-18T09-00-00-000Z_pid4242_0a1b2c3d.xctestproducts"
        let prepared = "build_sim_2026-11-18T09-00-00-000Z_pid4242_0a1b2c3d.xctestproducts"
        let foreign = "Mine.xctestproducts"
        let newest = "test_sim_2026-11-18T08-00-00-000Z_pid4241_0a1b2c3c.xctestproducts"
        try bundle(newest, in: folder, finished: true)
        try bundle(going, in: folder, finished: false)
        try bundle(prepared, in: folder, finished: true)
        try bundle(foreign, in: folder, finished: true)

        #expect(await drop() == 0)
        #expect(names(in: folder) == [newest, newest + ".mobilebuildmcp-completed", going, prepared, prepared + ".mobilebuildmcp-completed", foreign, foreign + ".mobilebuildmcp-completed"])
    }

    @Test func anotherCheckoutsWorkspaceStays() async throws {
        let other = folder(root: "/work/Other")
        let name = "test_sim_2026-11-18T09-00-00-000Z_pid4242_0a1b2c3d.xctestproducts"
        try bundle(name, in: other, finished: true)
        try bundle("test_sim_2026-11-18T10-00-00-000Z_pid4243_0a1b2c3e.xctestproducts", in: other, finished: true)

        #expect(await drop() == 0)
        #expect(names(in: other).contains(name))
    }

    @Test func noWorkspaceDropsNothing() async {
        #expect(await drop() == 0)
    }
}
