import Foundation

extension ResultBundle {
    /// One test's activities: each run's device and test-plan configuration, its steps, and the step that failed.
    func activities(of test: TestID) async -> String {
        await xcresulttool(["get", "test-results", "activities", "--test-id", test.xcresultID, "--path", path, "--compact"])
    }

    /// The tests that failed under any configuration, in the listing's order.
    func failedTests() async -> [TestID] {
        var seen: Set<TestID> = []
        return Self.nodes(Self.parse(await tests())).compactMap { node in
            guard node["nodeType"] as? String == "Test Case", node["result"] as? String == "Failed", let id = node["nodeIdentifier"] as? String else { return nil }
            let test = TestID(xcresultID: id)
            return seen.insert(test).inserted ? test : nil
        }
    }

    /// The newest result bundle MobileBuildMCP kept for a test run of this project, from any server: in its workspace's
    /// `result-bundles`, found as `RunLog` finds a log.
    public static func newest(project: URL, home: URL) -> String? {
        RunLog.find(in: "result-bundles", since: .distantPast, project: project, home: home) { $0.hasSuffix(".xcresult") }?.path
    }
}
