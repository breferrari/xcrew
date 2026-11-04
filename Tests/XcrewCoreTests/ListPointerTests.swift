import Foundation
import Testing
@testable import XcrewCore

/// A list that names a few and counts the rest says where they all are, so nothing reads as whole when it isn't; a list
/// kept nowhere else names every item.
@Suite struct ListPointerTests {
    static let seven = (1...7).map { "T\($0)" }

    @Test func aCountedListSaysWhereTheRestIs() {
        #expect(ResultBundle.joined(Self.seven, rest: "here") == "T1, T2, T3, T4, T5 and 2 more (here)")
        #expect(ResultBundle.joined(Array(Self.seven.prefix(3)), rest: "here") == "T1, T2 and T3")
    }

    @Test func expectedFailuresPastTheFirstFewPointToTheBundle() {
        let note = ResultBundle.expectedFailuresNote(summary: #"{"expectedFailures":7}"#, names: Self.seven)
        #expect(note?.contains("and 2 more (the run's result bundle lists them all)") == true, "\(note ?? "")")
    }

    @Test func repeatedRunsPastTheFirstFewPointToTheBundle() {
        let repeated = Self.seven.map { ResultBundle.Repeated(test: $0, failed: 2, passed: 1, runs: 3, verdict: .flaky) }
        #expect(ResultBundle.repetitionsNote(repeated)?.contains("and 2 more flaky or failing (the run's result bundle lists them all)") == true)
    }

    @Test func warningsPastTheFirstFewPointToTheResult() {
        let warnings = Self.seven.map { ToolOutput.Warning(message: "unused \($0)", path: "/p/A.swift", line: 1) }
        #expect(Report.warningsSentence(warnings, of: 9, rest: Report.inTheResult)?.contains("and 2 more (the result lists them all above)") == true)
    }

    /// Kept nowhere else, every item is named, however many: 60 here, each reaching the output.
    static let sixty = (1...60).map { "T" + String(repeating: "0", count: 3 - String($0).count) + String($0) }

    @Test func warningsKeptNowhereElseAreEachNamed() {
        let warnings = Self.sixty.map { ToolOutput.Warning(message: "unused \($0)", path: "/p/A.swift", line: 1) }
        let sentence = Report.warningsSentence(warnings, of: 60, rest: nil) ?? ""
        #expect(Self.sixty.allSatisfy { sentence.contains("unused \($0)") } && !sentence.contains("more"), "\(sentence)")
    }

    @Test func theEvidencesTestsPastTheFirstTenPointToTheLedger() {
        #expect(EvidencePack.more(12) == ["- +2 more; `/xcrew ledger` lists them all"])
    }

    /// Every changed line not run, every target not reached, and every file outside the coverage or changed after it.
    @Test func coverageListsNameEveryItem() {
        let coverage = ChangedLineCoverage(
            lines: Dictionary(uniqueKeysWithValues: Self.sixty.map { ("/p/Lines\($0).swift", [3: false]) }),
            outside: Self.sixty.map { "/p/Outside\($0).swift" },
            unreached: Self.sixty.map { .init(target: "Target\($0)", files: 1) },
            stale: Self.sixty.map { "/p/Stale\($0).swift" }
        ).sentence ?? ""
        for name in Self.sixty {
            #expect(coverage.contains("Lines\(name).swift:3") && coverage.contains("Target\(name)") && coverage.contains("Outside\(name).swift") && coverage.contains("Stale\(name).swift"), "\(name): \(coverage)")
        }
        #expect(!coverage.contains("more"), "\(coverage)")
    }

    /// The schemes sharing a plan, in the briefing and in the note on a run of no tests, name a few and point to the command
    /// that lists every one: a hook's context has a cap, and a large app's schemes would pass it.
    @Test func theSchemesSharingAPlanPointToTheCommandListingThem() {
        let plan = TestPlans.Configured(plan: "App", file: "/p/App.xctestplan", schemes: Self.sixty, configurations: ["A", "B"])
        #expect(plan.sentence.contains("schemes `T001`, `T002`, `T003`, `T004`, `T005` and 55 more (`xcrew plans` lists them all), runs"), "\(plan.sentence)")
    }

    @Test func theRunsFinishTimesAreEachNamed() {
        let finished = (1...60).map { Date(timeIntervalSince1970: 1_800_000_000 + Double($0) * 3_600) }
        let line = BranchCoverage(sentence: "all 3 changed lines that can run ran in these test runs.", finished: finished).line(lastCommit: nil)
        #expect(finished.allSatisfy { line.contains(EvidencePack.stamp($0)) } && !line.contains("more"), "\(line)")
    }

    @Test func aPlansConfigurationsPastTheFirstFewPointToItsFile() {
        let plan = TestPlans.Configured(plan: "App", file: "/p/App.xctestplan", schemes: ["App"], configurations: Self.seven)
        #expect(plan.sentence.contains("and 2 more (`/p/App.xctestplan` lists them all)"), "\(plan.sentence)")
    }
}
