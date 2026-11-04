import Foundation
import Testing
import XcrewCore
import XcrewTestSupport

/// A test's Machine reads nothing of the real Mac: a read outside its folders fails the test, loudly, and reads nothing.
struct RootedFilesTests {
    @Test func aReadOutsideItsFoldersFailsTheTestAndReadsNothing() {
        let files = RootedFiles(roots: [Project.temporary().root])
        var read: Data? = Data()
        withKnownIssue("a read outside the test's folders") { read = files.data(at: URL(fileURLWithPath: "/etc/hosts")) }
        var listed: [String]? = []
        withKnownIssue("a listing outside the test's folders") { listed = files.names(in: URL(fileURLWithPath: "/Applications")) }
        var found = true
        withKnownIssue("a look outside the test's folders") { found = files.exists(URL(fileURLWithPath: "/Applications")) }
        #expect(read == nil && listed == nil && !found)
    }

    @Test func aReadInsideItsFoldersReadsTheDisk() throws {
        let project = Project.temporary()
        project.write("hello", to: "a.txt")
        let files = RootedFiles(roots: [project.root])
        #expect(files.text(at: project.root.appending(path: "a.txt")) == "hello")
        #expect(files.names(in: project.root) == ["a.txt"])
        #expect(files.exists(project.root.appending(path: "a.txt")))
    }

    /// A test's Machine whose home is the Mac's own, or whose cache is in the Mac's own caches, fails the test as it's
    /// made: what the Machine's home and cache hold is read directly, so they must be folders the test made.
    @Test func aTestMachineWithTheMacsHomeOrCachesFailsTheTest() {
        let mine = FileManager.default.homeDirectoryForCurrentUser
        withKnownIssue("the Mac's own home") {
            _ = Machine(environment: [:], home: mine, runner: FakeRunner(), files: RootedFiles(roots: []))
        }
        withKnownIssue("the Mac's own caches") {
            _ = Machine(environment: ["XCREW_CACHE": mine.appending(path: "Library/Caches/xcrew").path], home: Project.temporary().root, runner: FakeRunner(), files: RootedFiles(roots: []))
        }
        _ = Machine(environment: [:], home: Project.temporary().root, runner: FakeRunner(), files: RootedFiles(roots: []))
    }
}
