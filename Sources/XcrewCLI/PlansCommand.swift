import Foundation
import XcrewCore

/// `xcrew plans`: every test plan the project's schemes run by default that runs each test under several
/// configurations, each with every scheme it's the default of: the list the briefing and a run of no tests point to.
struct PlansCommand: Command {
    let name = "plans"
    let usage = ["plans   every test plan here that runs each test under several configurations, with every scheme it's the default of"]

    func run(_ invocation: Invocation) async throws -> Int32 {
        invocation.print(TestPlans.listing(for: invocation.context.project) ?? "xcrew: no test plan here runs each test under several configurations")
        return 0
    }
}
