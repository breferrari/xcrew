import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

@Suite struct HookTests {
    @Test func readsTheEventItNeeds() async {
        let event = HookEvent(json: Data(#"{"hook_event_name":"SessionStart","cwd":"/work/App","source":"startup"}"#.utf8))
        #expect(event == HookEvent(name: "SessionStart", cwd: "/work/App"))
        #expect(HookEvent(json: Data("not json".utf8)).name == "SessionStart")
    }

    @Test func replyShape() async throws {
        let json = HookReply(event: HookEvent(name: "SessionStart"), context: "rules").json
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let specific = try #require(object["hookSpecificOutput"] as? [String: String])
        #expect(specific == ["hookEventName": "SessionStart", "additionalContext": "rules"])
    }

    @Test func briefingOnlyInAppleProjects() async {
        let elsewhere = SessionBriefing(project: .temporary(), machine: CheckContext.fake().machine)
        #expect(elsewhere.text(routing: "rules") == nil)

        let project = Project.temporary(containing: ["App.xcodeproj"])
        let text = SessionBriefing(project: project, machine: CheckContext.fake(project: project).machine).text(routing: "rules\n")
        #expect(text?.hasPrefix("rules\n- **xcrew:** MobileBuildMCP isn't installed") == true)
        #expect(text?.contains("/xcrew:setup") == true)
    }

    @Test func briefingForAnAppInASubfolder() async {
        let project = Project.temporary(containing: [".git", "ios/Tuist.swift"])
        let text = SessionBriefing(project: project, machine: CheckContext.fake(project: project).machine).text(routing: "rules\n")
        #expect(text?.hasPrefix("rules\n- **xcrew:** MobileBuildMCP isn't installed") == true)
    }

    @Test func generatedProjectsCountBeforeTheirWorkspaceExists() async {
        let project = Project.temporary()
        project.write("", to: "Project.swift")
        #expect(project.isApplePlatformProject)
    }
}
