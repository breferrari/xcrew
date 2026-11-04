import Foundation
import Testing
@testable import XcrewCLI
@testable import XcrewCore
import XcrewTestSupport

/// `xcrew plans`: every test plan the project's schemes run by default that runs each test under several
/// configurations, each with every scheme it's the default of, as the briefing and the note on a run of no tests point to.
@Suite struct PlansCommandTests {
    /// Every plan and every scheme, however many: 60 schemes share one plan here.
    @Test func everyPlanAndEverySchemeIsListed() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        let schemes = (1...60).map { "S" + String(repeating: "0", count: 3 - String($0).count) + String($0) }
        for scheme in schemes { project.writeScheme(scheme, plan: "Shared.xctestplan") }
        project.write(#"{"configurations":[{"name":"Light"},{"name":"Dark"}],"testTargets":[],"version":1}"#, to: "Shared.xctestplan")
        project.writeScheme("Other", plan: "Other.xctestplan")
        project.write(#"{"configurations":[{"name":"One"},{"name":"Two"}],"testTargets":[],"version":1}"#, to: "Other.xctestplan")
        let run = await Run("plans", context: .fake(FakeRunner(), project: project))
        #expect(run.status == 0)
        #expect(schemes.allSatisfy { run.text.contains("`\($0)`") } && !run.text.contains("more"), "\(run.text)")
        #expect(run.text.contains("Test plan `Other`, the default of scheme `Other`, runs each test under each of its configurations: One and Two."), "\(run.text)")
    }

    /// A project none of whose plans runs each test under several configurations says so.
    @Test func noPlanOfSeveralConfigurationsIsSaidSo() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        let run = await Run("plans", context: .fake(FakeRunner(), project: project))
        #expect(run.text == "xcrew: no test plan here runs each test under several configurations", "\(run.text)")
    }
}
