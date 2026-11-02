import Foundation
import Testing
@testable import XcrewCore

/// A flaky mark turns green only after enough passes in a row that a test failing at the rate it was seen failing would
/// pass them all under 5% of the time: `n ≥ ln 0.05 / ln(1 − rate)`.
@Suite struct FlakyMarkTests {
    static func repeated(failed: Int, of runs: Int) -> ResultBundle.Repeated {
        let verdict: ResultBundle.Verdict = failed == 0 ? .passed : failed == runs ? .real : .flaky
        return .init(test: "Suite/test", failed: failed, passed: runs - failed, runs: runs, verdict: verdict)
    }

    /// The figures worked out by hand: 2 of 5 needs 6 (ln 0.05 / ln 0.6 = 5.86), 1 of 5 needs 14 (13.4), 1 of 20 needs 59
    /// (58.4).
    @Test(arguments: [(2, 5, 6), (1, 5, 14), (1, 20, 59)])
    func thePassesNeededAreThoseThatWouldAllPassUnderFivePercentOfTheTime(failed: Int, runs: Int, needed: Int) {
        #expect(FlakyMark(test: "Suite/test", failed: failed, runs: runs, passes: 0).needed == needed)
    }

    @Test func aFlakyRunMarksTheTestWithItsRate() throws {
        let mark = try #require(FlakyMark.after(nil, Self.repeated(failed: 1, of: 5)))
        #expect(mark == FlakyMark(test: "Suite/test", failed: 1, runs: 5, passes: 0))
        #expect(!mark.isSettled)
    }

    /// Passes add up across repeated runs, and the mark settles once they reach the number needed.
    @Test func passesAddUpUntilEnough() throws {
        let found = FlakyMark(test: "Suite/test", failed: 1, runs: 5, passes: 0)
        let ten = try #require(FlakyMark.after(found, Self.repeated(failed: 0, of: 10)))
        #expect(ten == FlakyMark(test: "Suite/test", failed: 1, runs: 5, passes: 10))
        #expect(!ten.isSettled)
        let fourteen = try #require(FlakyMark.after(ten, Self.repeated(failed: 0, of: 4)))
        #expect(fourteen.passes == 14)
        #expect(fourteen.isSettled)
    }

    /// A failure resets the passes, and folds every run since the mark, the passes included, into the rate.
    @Test func aFailureResetsThePassesAndFoldsIntoTheRate() throws {
        let passing = FlakyMark(test: "Suite/test", failed: 1, runs: 5, passes: 10)
        let failed = try #require(FlakyMark.after(passing, Self.repeated(failed: 1, of: 5)))
        #expect(failed == FlakyMark(test: "Suite/test", failed: 2, runs: 20, passes: 0))
        #expect(failed.needed == 29)
    }

    /// Failing every run is a real failure, no longer flaky; a run that says neither leaves the mark as it was; a test
    /// never marked isn't marked by passing.
    @Test func aRealFailureEndsTheMarkAndNothingElseStartsOne() {
        let mark = FlakyMark(test: "Suite/test", failed: 1, runs: 5, passes: 3)
        #expect(FlakyMark.after(mark, Self.repeated(failed: 5, of: 5)) == nil)
        #expect(FlakyMark.after(mark, .init(test: "Suite/test", failed: 0, passed: 0, runs: 5, verdict: .none)) == mark)
        #expect(FlakyMark.after(nil, Self.repeated(failed: 0, of: 5)) == nil)
    }
}
