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
}
