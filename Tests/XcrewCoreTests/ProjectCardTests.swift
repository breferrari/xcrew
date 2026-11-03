import Foundation
import Testing

@testable import XcrewCore
import XcrewTestSupport

/// The project card the mod saves and the session-start hook prints, by the rules the mod's own card followed when it
/// was sent with a conversation's first message: per folder and branch, dropped once its data is older than the history
/// is kept.
@Suite struct ProjectCardTests {
    static let now = Date(timeIntervalSince1970: 1_793_361_600)
    static let card = "Xcrew's notes on this project, from earlier runs:\n- build_sim · App: usually 0:45"

    func machine() -> Machine {
        CheckContext.fake(project: .temporary()).machine
    }

    func entry(folder: String = "/work/App", branch: String = "feat/card", age: TimeInterval = 2 * 3600, oldest: TimeInterval? = nil, text: String? = Self.card) -> ProjectCard.Entry {
        ProjectCard.Entry(folder: folder, branch: branch, updated: (Self.now.timeIntervalSince1970 - age) * 1000, oldest: oldest.map { (Self.now.timeIntervalSince1970 - $0) * 1000 }, text: text)
    }

    /// The card says when its data was written, so Claude reads it as the last recorded state, not a live one.
    @Test func theCardForThisFolderAndBranchSaysHowOldItIs() {
        let machine = machine()
        ProjectCard.save(entry(), on: machine, now: Self.now)
        #expect(ProjectCard.text(folder: "/work/App", branch: "feat/card", now: Self.now, on: machine) == "Xcrew's notes on this project, from earlier runs, as of the run 2 h ago:\n- build_sim · App: usually 0:45")
    }

    /// A branch switched since the last run must never show the old branch's red tests.
    @Test func anotherBranchOrFolderGetsNoCard() {
        let machine = machine()
        ProjectCard.save(entry(), on: machine, now: Self.now)
        #expect(ProjectCard.text(folder: "/work/App", branch: "main", now: Self.now, on: machine) == nil)
        #expect(ProjectCard.text(folder: "/work/Shop", branch: "feat/card", now: Self.now, on: machine) == nil)
    }

    /// The mod's own rule: stale once more than the history's two weeks old, and not a moment before.
    @Test func aCardOlderThanTheHistoryIsKeptIsDropped() {
        let machine = machine()
        ProjectCard.save(entry(age: 14 * 24 * 3600), on: machine, now: Self.now)
        #expect(ProjectCard.text(folder: "/work/App", branch: "feat/card", now: Self.now, on: machine)?.contains("as of the run 14 d ago") == true)
        ProjectCard.save(entry(age: 14 * 24 * 3600 + 60), on: machine, now: Self.now)
        #expect(ProjectCard.text(folder: "/work/App", branch: "feat/card", now: Self.now, on: machine) == nil)
    }

    /// A save with nothing to say clears what an earlier one said, and leaves the other folders' cards.
    @Test func aSaveWithoutTextClearsThatCardAlone() {
        let machine = machine()
        ProjectCard.save(entry(), on: machine, now: Self.now)
        ProjectCard.save(entry(folder: "/work/Shop"), on: machine, now: Self.now)
        ProjectCard.save(entry(text: nil), on: machine, now: Self.now)
        #expect(ProjectCard.text(folder: "/work/App", branch: "feat/card", now: Self.now, on: machine) == nil)
        #expect(ProjectCard.text(folder: "/work/Shop", branch: "feat/card", now: Self.now, on: machine) != nil)
    }

    /// A newer xcrew may write a format this one can't read: it reads nothing and leaves the file alone.
    @Test func aNewerFormatIsIgnoredNotOverwritten() throws {
        let machine = machine()
        let file = ProjectCard.file(folder: "/work/App", branch: "feat/card", on: machine)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let newer = #"{"version":99,"folder":"/work/App","branch":"feat/card","updated":1793354400000,"text":"x"}"#
        try Data(newer.utf8).write(to: file)
        #expect(ProjectCard.text(folder: "/work/App", branch: "feat/card", now: Self.now, on: machine) == nil)
        ProjectCard.save(entry(), on: machine, now: Self.now)
        #expect(try String(contentsOf: file, encoding: .utf8) == newer)
    }

    @Test func unknownFieldsAreIgnored() throws {
        let machine = machine()
        let file = ProjectCard.file(folder: "/work/App", branch: "feat/card", on: machine)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version":1,"extra":true,"folder":"/work/App","branch":"feat/card","updated":1793354400000,"text":"Notes:\n- a","later":[1]}"#.utf8).write(to: file)
        #expect(ProjectCard.text(folder: "/work/App", branch: "feat/card", now: Self.now, on: machine) == "Notes, as of the run 2 h ago:\n- a")
    }

    /// Each card is a file of its own, so a save replaces only its own: two sessions saving at once can't lose the other's.
    @Test func eachCardIsAFileOfItsOwn() throws {
        let machine = machine()
        ProjectCard.save(entry(), on: machine, now: Self.now)
        ProjectCard.save(entry(folder: "/work/Shop"), on: machine, now: Self.now)
        try Data("not a card".utf8).write(to: ProjectCard.file(folder: "/work/Shop", branch: "feat/card", on: machine))
        #expect(ProjectCard.text(folder: "/work/App", branch: "feat/card", now: Self.now, on: machine) != nil)
    }

    /// A card is dropped once its oldest line is older than the history is kept, as the mod drops each line by its own
    /// age; its first line still says how new its newest is.
    @Test func aCardWhoseOldestLineIsStaleIsDropped() {
        let machine = machine()
        ProjectCard.save(entry(age: 24 * 3600, oldest: 15 * 24 * 3600), on: machine, now: Self.now)
        #expect(ProjectCard.text(folder: "/work/App", branch: "feat/card", now: Self.now, on: machine) == nil)
        ProjectCard.save(entry(age: 24 * 3600, oldest: 13 * 24 * 3600), on: machine, now: Self.now)
        #expect(ProjectCard.text(folder: "/work/App", branch: "feat/card", now: Self.now, on: machine)?.contains("as of the run 1 d ago") == true)
    }

    /// The same key the mod's ledger uses: the branch, else the commit, else nothing outside git.
    @Test func theBranchKeyIsTheMods() {
        #expect(ProjectCard.branchKey(.branch("feat/card")) == "feat/card")
        #expect(ProjectCard.branchKey(.commit("0123456789abcdef")) == "commit 0123456789abcdef")
        #expect(ProjectCard.branchKey(nil) == "")
    }
}
