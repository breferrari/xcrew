import Foundation
import Testing
@testable import XcrewCLI
@testable import XcrewCore
import XcrewTestSupport

/// `xcrew flaky`: the ledger's flaky marks after a repeated run, worked out by the CLI and kept by the mod.
@Suite struct FlakyCommandTests {
    @Test func theMarksAfterARunAreAnsweredWithThePassesNeeded() async throws {
        let stdin = #"{"marks":[{"test":"Suite/old","failed":1,"runs":5,"passes":10}],"repeated":[{"test":"Suite/old","failed":0,"passed":4,"runs":4,"verdict":"passed"},{"test":"Suite/new","failed":2,"passed":3,"runs":5,"verdict":"flaky"},{"test":"Suite/real","failed":5,"passed":0,"runs":5,"verdict":"real"}]}"#
        let run = await Run("flaky", stdin: stdin)
        #expect(run.status == 0)
        let answer = try #require(try JSONSerialization.jsonObject(with: Data(run.text.utf8)) as? [[String: Any]])
        #expect(answer.count == 2)
        #expect(NSDictionary(dictionary: answer[0]) == ["test": "Suite/old", "failed": 1, "runs": 5, "passes": 14, "needed": 14, "settled": true])
        #expect(NSDictionary(dictionary: answer[1]) == ["test": "Suite/new", "failed": 2, "runs": 5, "passes": 0, "needed": 6, "settled": false])
    }

    @Test func anythingButTheMarksAndTheRunIsAUsageError() async {
        let run = await Run("flaky", stdin: "not json")
        #expect(run.status != 0)
    }
}
