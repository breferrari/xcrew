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

    /// A test's exported attachments, moved out of the export's folder to one the caller removes, for reading that
    /// takes awaiting; nil when the move failed.
    func exportedAttachments(of test: TestID) async -> URL? {
        await attachments(of: test, onlyFailures: false) { export in
            let kept = FileManager.default.temporaryDirectory.appending(path: "xcrew-look-\(UUID().uuidString)")
            return (try? FileManager.default.moveItem(at: export, to: kept)) != nil ? kept : nil
        }
    }

    /// The newest result bundle MobileBuildMCP kept for a test run of this project, from any server: its workspace's
    /// `result-bundles`, which it keys as it keys `logs` (`RunLog`), under the root as given and as its real path. It
    /// removes bundles a few days old.
    public static func newest(project: URL, home: URL) -> String? {
        let workspaces = home.appending(path: "Library/Developer/MobileBuildMCP/workspaces")
        let roots = [project.path, ProjectLayout.canonical(project)]
        let bundles = Set(roots.map(RunLog.workspaceKey(root:))).flatMap { key in
            let folder = workspaces.appending(path: key).appending(path: "result-bundles")
            return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".xcresult") }.map { folder.appending(path: $0) }
        }
        let modified = { (bundle: URL) in (try? bundle.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast }
        return bundles.max { modified($0) < modified($1) }?.path
    }
}
