import Foundation
import Testing
@testable import XcrewCLI
import XcrewCore
import XcrewTestSupport

/// `xcrew concurrency` in words and as JSON, from a log named or the newest one, and what it says with none.
@Suite struct ConcurrencyCommandTests {
    func project() -> Project {
        let project = Project.temporary(containing: ["Concurrency.xcodeproj"])
        project.write(#"{ "files": [ { "kind": "folder", "path": "Kit", "target-membership": [ "Kit" ] } ], "targets": [ { "name": "Kit", "id": "K", "product-type": "framework" } ] }"#, to: "Concurrency.xcodeproj/project.xcproj")
        let root = project.canonicalRoot
        project.write("""
            \(root)/Kit/Kit.swift:1:12: warning: var 'sharedCount' is not concurrency-safe [#MutableGlobalVariable]
            \(root)/Kit/Kit.swift:24:17: warning: sending 'box' risks causing data races [#RegionIsolation::SendingRisksDataRace]
            \(root)/Kit/Kit.swift:1:12: warning: var 'sharedCount' is not concurrency-safe [#MutableGlobalVariable]
            \(root)/Kit/Kit.swift:9:16: warning: stored property 'box' has non-Sendable type 'Box'

            """, to: "build.log")
        return project
    }

    @Test func wordsGiveTheCountsByGroupAndModule() async {
        let project = project()
        let run = await Run("concurrency", "--log", project.root.appending(path: "build.log").path, context: .fake(project: project))
        #expect(run.status == 0)
        #expect(run.output == [
            "2 Swift concurrency diagnostics in 1 module:",
            "  MutableGlobalVariable 1: Kit 1",
            "  SendingRisksDataRace 1: Kit 1",
            "1 Swift diagnostic carries no compiler group, so it isn't counted: only its text would say what it's about.",
            "Which groups are about concurrency comes from their names: no group docs were found for the Xcode that built it.",
            "A build that compiled only some files logs only theirs.",
        ])
    }

    @Test func jsonCarriesTheReport() async throws {
        let project = project()
        let run = await Run("concurrency", "--json", "--log", project.root.appending(path: "build.log").path, context: .fake(project: project))
        let report = try JSONDecoder().decode(ConcurrencyReport.self, from: Data(run.text.utf8))
        #expect(report.count == 2)
        #expect(report.modules.map(\.name) == ["Kit"])
    }

    @Test func withNoLogItSaysSo() async {
        let run = await Run("concurrency", context: .fake(project: project()))
        #expect(run.status == 1)
        #expect(run.output == ["xcrew: MobileBuildMCP has no build or test log for this project yet; pass --log <file> for another"])
    }

    /// `--changed` where git can't read the change says so, and doesn't call the whole log the branch's.
    @Test func changedLinesGitCantReadAreSaid() async {
        let project = project()
        let run = await Run("concurrency", "--changed", "--log", project.root.appending(path: "build.log").path, context: .fake(project: project))
        #expect(run.output.first?.hasPrefix("The branch's changed lines couldn't be read (") == true, "\(run.output)")
        #expect(run.output.dropFirst().first == "2 Swift concurrency diagnostics in 1 module:")
    }
}
