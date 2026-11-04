import Foundation
import Testing
@testable import XcrewCLI
@testable import XcrewCore
import XcrewTestSupport

/// `xcrew gone`: which of the checkouts the mod stored something for aren't there any more.
@Suite struct GoneCommandTests {
    @Test func aFolderThatIsntThereIsGoneAndOneThatIsIsnt() async throws {
        let project = Project.temporary()
        let removed = project.root.deletingLastPathComponent().appending(path: "\(project.root.lastPathComponent)-removed").path
        let text = await Run("gone", project.root.path, removed, context: .fake(FakeRunner(), project: project, files: LocalFiles())).text
        #expect(try JSONDecoder().decode(GoneCommand.Answer.self, from: Data(text.utf8)) == .init(gone: [removed]))
    }

    /// A folder on a volume that isn't mounted, as an external drive taken out, isn't gone: its volume is.
    @Test func aFolderOnAVolumeThatIsntMountedIsntGone() async throws {
        let project = Project.temporary()
        let unmounted = "/Volumes/xcrew-unmounted-\(UUID().uuidString)/App"
        let text = await Run("gone", unmounted, context: .fake(FakeRunner(), project: project, files: LocalFiles())).text
        #expect(try JSONDecoder().decode(GoneCommand.Answer.self, from: Data(text.utf8)) == .init(gone: []))
    }

    /// One missing from a volume that is mounted is gone, as one missing from the startup volume is.
    @Test func aFolderMissingFromAMountedVolumeIsGone() {
        let startup = Project.temporary().root.appending(path: "App").path
        #expect(GoneCommand.gone(["/Volumes/Drive/App", "/Volumes/Other/App", startup], mounted: ["/", "/Volumes/Drive"], files: LocalFiles()) == ["/Volumes/Drive/App", startup])
    }

    /// A folder the CLI isn't let look at, as macOS's privacy rules can refuse, isn't gone: only one the system says
    /// doesn't exist is.
    @Test func aFolderThatCantBeLookedAtIsntGone() throws {
        let project = Project.temporary()
        let locked = project.root.appending(path: "locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        #expect(GoneCommand.gone([locked.appending(path: "App").path], mounted: ["/"], files: LocalFiles()) == [])
    }

    /// An empty or relative name is no folder to look for.
    @Test func onlyAnAbsolutePathCanBeGone() {
        #expect(GoneCommand.gone(["", "work/App"], mounted: ["/"], files: LocalFiles()) == [])
    }

    /// Foundation lists the startup volume as `/`, and a volume under `/Volumes` by its folder there, which the rule reads.
    @Test func theMountedVolumesListTheStartupVolume() {
        #expect(GoneCommand.mounted.contains("/"))
    }

    /// A folder whose parent is gone too isn't counted: an unmounted share's or drive's folders go with their mount, where
    /// a removed worktree leaves the folder that held it.
    @Test func aFolderWhoseParentIsMissingTooIsntGone() {
        let project = Project.temporary()
        let removed = project.root.appending(path: "trees/feature").path
        let outside = project.root.appending(path: "share-\(UUID().uuidString)/App").path
        try? FileManager.default.createDirectory(atPath: project.root.appending(path: "trees").path, withIntermediateDirectories: true)
        #expect(GoneCommand.gone([removed, outside], mounted: ["/"], files: LocalFiles()) == [removed])
    }
}
