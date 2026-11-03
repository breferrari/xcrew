import Foundation
import Testing
@testable import XcrewCore

/// A list that names a few and counts the rest says where they all are, or that no list of them is kept, so nothing
/// reads as whole when it isn't.
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

    @Test func warningsPastTheFirstFewPointToTheResultOrSayNoListIsKept() {
        let warnings = Self.seven.map { ToolOutput.Warning(message: "unused \($0)", path: "/p/A.swift", line: 1) }
        #expect(Report.warningsSentence(warnings, of: 9, rest: Report.inTheResult)?.contains("and 2 more (the result lists them all above)") == true)
        #expect(Report.warningsSentence(warnings, of: 9, rest: ResultBundle.noList)?.contains("and 2 more (no list of them is kept)") == true)
    }

    @Test func theEvidencesTestsPastTheFirstTenPointToTheLedger() {
        #expect(EvidencePack.more(12) == ["- +2 more; `/xcrew ledger` lists them all"])
    }

    @Test func coverageListsSayNoListOfTheRestIsKept() {
        let outside = ChangedLineCoverage(outside: Self.seven.map { "/p/\($0).swift" })
        #expect(outside.sentence?.contains("and 2 more (no list of them is kept)") == true, "\(outside.sentence ?? "")")
    }

    @Test func aPlansConfigurationsPastTheFirstFewPointToItsFile() {
        let plan = TestPlans.Configured(plan: "App", file: "/p/App.xctestplan", schemes: ["App"], configurations: Self.seven)
        #expect(plan.sentence.contains("and 2 more (`/p/App.xctestplan` lists them all)"), "\(plan.sentence)")
    }
}
