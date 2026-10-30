import Foundation

extension ResultBundle {
    /// One test's activities: each run's device and test-plan configuration, its steps, and the step that failed.
    func activities(of test: TestID) async -> String {
        await xcresulttool(["get", "test-results", "activities", "--test-id", test.xcresultID, "--path", path, "--compact"])
    }

    /// The tests that failed under any configuration, in the listing's order; nil when the listing can't be read.
    func failedTests() async -> [TestID]? {
        guard let listing = Self.parse(await tests()) else { return nil }
        var seen: Set<TestID> = []
        return Self.nodes(listing).compactMap { node in
            guard node["nodeType"] as? String == "Test Case", node["result"] as? String == "Failed", let id = node["nodeIdentifier"] as? String else { return nil }
            let test = TestID(xcresultID: id)
            return seen.insert(test).inserted ? test : nil
        }
    }

    /// What MobileBuildMCP writes beside a result bundle once its run has finished (`utils/result-bundle-path.js`).
    static let completionMark = ".mobilebuildmcp-completed"

    /// The newest result bundle MobileBuildMCP kept for a finished test run of this project, from this session's own
    /// servers when there's a session to tell: in its workspace's `result-bundles`, found as `RunLog` finds a log. A run
    /// still going has no completion mark yet; a MobileBuildMCP that writes none has its newest bundle read instead.
    public static func newest(project: URL, machine: Machine) async -> String? {
        let finished = await RunLog.find(in: "result-bundles", since: .distantPast, project: project, machine: machine) { $0.hasSuffix(".xcresult" + completionMark) }
        if let finished { return String(finished.path.dropLast(completionMark.count)) }
        return await RunLog.find(in: "result-bundles", since: .distantPast, project: project, machine: machine) { $0.hasSuffix(".xcresult") }?.path
    }
}
