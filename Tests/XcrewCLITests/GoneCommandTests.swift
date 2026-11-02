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
        let text = await Run("gone", project.root.path, removed, context: .fake(FakeRunner(), project: project)).text
        #expect(try JSONDecoder().decode(GoneCommand.Answer.self, from: Data(text.utf8)) == .init(gone: [removed]))
    }
}
