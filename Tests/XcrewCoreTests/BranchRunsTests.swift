import Foundation
import Testing
@testable import XcrewCore

/// Which test runs are this branch's: written while the checkout's HEAD was on it, as its reflog records each checkout,
/// and since the branch's merge base.
@Suite struct BranchRunsTests {
    static func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    /// `git reflog show HEAD --date=unix --format=%gd%x09%gs`, newest first: a first commit on main, then feat checked out,
    /// main again, and feat again.
    static let reflog = """
        HEAD@{400}\tcheckout: moving from main to feat
        HEAD@{300}\tcheckout: moving from feat to main
        HEAD@{200}\tcheckout: moving from main to feat
        HEAD@{100}\tcommit (initial): first
        """

    /// A run written while main was checked out is left out, though it's newer than one of feat's.
    @Test func aRunWrittenOnAnotherBranchIsLeftOut() {
        let bundles = [("/r/a.xcresult", Self.at(250)), ("/r/b.xcresult", Self.at(350)), ("/r/c.xcresult", Self.at(450))]
        let chosen = BranchRuns.chosen(bundles, reflog: Self.reflog, branch: "feat", mergeBase: Self.at(100), lastCommit: Self.at(420))
        #expect(chosen.paths == ["/r/c.xcresult", "/r/a.xcresult"])
        #expect(chosen.onlySinceLastCommit == false)
    }

    /// A run from before the branch's merge base isn't its own, though HEAD was on a branch of that name.
    @Test func aRunOlderThanTheMergeBaseIsLeftOut() {
        let bundles = [("/r/a.xcresult", Self.at(250)), ("/r/c.xcresult", Self.at(450))]
        #expect(BranchRuns.chosen(bundles, reflog: Self.reflog, branch: "feat", mergeBase: Self.at(260), lastCommit: Self.at(420)).paths == ["/r/c.xcresult"])
    }

    /// With no reflog to read, only runs since the last commit count, and the choice says so.
    @Test func withNoReflogOnlyRunsSinceTheLastCommitCount() {
        let bundles = [("/r/a.xcresult", Self.at(250)), ("/r/c.xcresult", Self.at(450))]
        let chosen = BranchRuns.chosen(bundles, reflog: nil, branch: "feat", mergeBase: Self.at(100), lastCommit: Self.at(420))
        #expect(chosen.paths == ["/r/c.xcresult"])
        #expect(chosen.onlySinceLastCommit == true)
    }

    /// A reflog with no checkout, as a fresh clone's, had HEAD on the branch from its first entry on.
    @Test func aReflogWithNoCheckoutHadTheBranchThroughout() {
        let bundles = [("/r/a.xcresult", Self.at(50)), ("/r/c.xcresult", Self.at(450))]
        let chosen = BranchRuns.chosen(bundles, reflog: "HEAD@{100}\tclone: from git@host:repo.git", branch: "main", mergeBase: nil, lastCommit: Self.at(420))
        #expect(chosen.paths == ["/r/c.xcresult"])
    }
}
