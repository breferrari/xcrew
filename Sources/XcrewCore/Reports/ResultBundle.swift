import Foundation

/// What a run's result bundle adds to a failing MobileBuildMCP test run: where each failure
/// happened (on parallel simulator clones xcodebuild logs none), a crash's exception and frames,
/// why each skipped test was skipped, and the expected failures its counts leave out. One
/// `xcresulttool` call per test, each well under a second.
public struct ResultBundle: Sendable {
    public struct Skip: Sendable, Equatable {
        public let reason: String?
        public let seconds: Double
    }

    public let path: String
    let runner: any CommandRunning
    /// A fresh folder for one crash log export; tests pass one they have filled.
    let exportFolder: @Sendable () -> URL

    public init(path: String, runner: any CommandRunning, exportFolder: @escaping @Sendable () -> URL = { FileManager.default.temporaryDirectory.appending(path: "xcrew-crash-\(UUID().uuidString)") }) {
        self.path = path
        self.runner = runner
        self.exportFolder = exportFolder
    }

    /// The run's `.xcresult`: from a passing run's JSON, or the workspace folder and bundle path a failing run's text lists.
    public static func path(in text: String, home: String) -> String? {
        let fromJson = (ToolOutput.object(text)?["data"] as? [String: Any]).flatMap { $0["artifacts"] as? [String: Any] }?["xcresultPath"] as? String
        if let fromJson { return expandingHome(fromJson, home) }
        guard let folder = text.firstMatch(of: #/(?m)└── (~?\/\S+\/)\s*$/#)?.1,
              let bundle = text.firstMatch(of: #/(result-bundles\/\S+\.xcresult) — Result Bundle/#)?.1
        else { return nil }
        return expandingHome(String(folder), home) + bundle
    }

    static func expandingHome(_ path: String, _ home: String) -> String {
        path.hasPrefix("~") ? home + path.dropFirst() : path
    }

    // MARK: Reading xcresulttool's output

    /// Every node of a JSON value, breadth first.
    static func nodes(_ json: Any?) -> [[String: Any]] {
        var queue: [Any] = json.map { [$0] } ?? []
        var found: [[String: Any]] = []
        while !queue.isEmpty {
            let node = queue.removeFirst()
            if let array = node as? [Any] {
                queue.append(contentsOf: array)
            } else if let object = node as? [String: Any] {
                found.append(object)
                queue.append(contentsOf: object.keys.sorted().compactMap { object[$0] })
            }
        }
        return found
    }

    static func parse(_ text: String) -> Any? {
        try? JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    /// The first source location in `xcresulttool get test-results test-details` output, as `path:line`.
    public static func sourceLocation(details: String) -> String? {
        for node in nodes(parse(details)) {
            if let location = node["sourceLocation"] as? [String: Any], let file = location["filePath"] as? String, let line = location["lineNumber"] as? Int {
                return "\(file):\(line)"
            }
        }
        return nil
    }

    /// Each skipped test in `xcresulttool get test-results tests` output, keyed `Suite/test`, in the
    /// listing's order, with why it was skipped (its `Test skipped - <reason>` message) and how long it ran.
    public static func skippedTests(listing: String) -> [(test: String, skip: Skip)] {
        nodes(parse(listing)).compactMap { node in
            guard node["nodeType"] as? String == "Test Case", node["result"] as? String == "Skipped",
                  let identifier = node["nodeIdentifier"] as? String
            else { return nil }
            let message = (node["children"] as? [[String: Any]])?.first { $0["nodeType"] as? String == "Skip Message" }?["name"] as? String
            let reason = message.map { $0.hasPrefix("Test skipped - ") ? String($0.dropFirst("Test skipped - ".count)) : $0 }
            let parts = identifier.split(separator: "/", maxSplits: 1).map(String.init)
            return (FailureNotes.key(parts.first ?? "", parts.count > 1 ? parts[1] : ""), Skip(reason: reason, seconds: node["durationInSeconds"] as? Double ?? 0))
        }
    }

    /// Frames of the crashed thread shown: enough to reach the test's own code from the crash.
    static let topFrames = 5

    /// A crash log's exception and the top frames of the thread that crashed, as `image  symbol`.
    public static func crashSummary(log: String) -> [String]? {
        guard let newline = log.firstIndex(of: "\n"),
              let report = parse(String(log[log.index(after: newline)...])) as? [String: Any],
              let threads = report["threads"] as? [[String: Any]],
              let faulting = report["faultingThread"] as? Int, threads.indices.contains(faulting),
              let frames = threads[faulting]["frames"] as? [[String: Any]]
        else { return nil }
        let images = report["usedImages"] as? [[String: Any]] ?? []
        let exception = report["exception"] as? [String: Any]
        let crashed = (exception?["type"] as? String).map { type in "crashed: \(type)\((exception?["signal"] as? String).map { " (\($0))" } ?? "")" }
        let top = frames.prefix(topFrames).map { frame in
            let index = frame["imageIndex"] as? Int ?? -1
            let image = images.indices.contains(index) ? images[index]["name"] as? String ?? "?" : "?"
            return "\(image)  \(frame["symbol"] as? String ?? "?")"
        }
        return (crashed.map { [$0] } ?? []) + top
    }

    /// The tests in `xcresulttool get test-results tests` output that ran as expected failures, in the listing's order.
    public static func expectedFailures(listing: String) -> [String] {
        nodes(parse(listing)).compactMap { node in
            node["nodeType"] as? String == "Test Case" && node["result"] as? String == "Expected Failure" ? node["nodeIdentifier"] as? String : nil
        }
    }

    /// Expected failures named in the note before the rest are counted.
    static let mostNamed = 5

    /// A note naming a run's expected failures (`XCTExpectFailure`), from `xcresulttool get test-results
    /// summary` and the tests the list names: MobileBuildMCP's counts leave them out, so passed + failed
    /// + skipped falls short of the tests that ran. Nil when there are none.
    public static func expectedFailuresNote(summary: String, names: [String] = []) -> String? {
        let counts = parse(summary) as? [String: Any]
        let expected = counts?["expectedFailures"] as? Int ?? 0
        guard expected > 0 else { return nil }
        let tests = expected == 1 ? "1 test also ran as an expected failure" : "\(expected) tests also ran as expected failures"
        let total = (counts?["totalTestCount"] as? Int).map { ": \($0) tests ran in all" } ?? ""
        return "xcrew: \(tests) (XCTExpectFailure)\(listed(names)). They count as neither passed nor failed in the result\(total)."
    }

    /// `: A, B and C`, or `: A, B, C, D, E and 2 more`; nothing without names.
    static func listed(_ names: [String]) -> String {
        guard let last = names.last else { return "" }
        if names.count > mostNamed { return ": " + names.prefix(mostNamed).joined(separator: ", ") + " and \(names.count - mostNamed) more" }
        return names.count == 1 ? ": \(last)" : ": " + names.dropLast().joined(separator: ", ") + " and \(last)"
    }

    // MARK: Asking xcresulttool

    func xcresulttool(_ arguments: [String]) async -> String {
        let ran = await runner.run(["xcrun", "xcresulttool"] + arguments, stdin: nil, timeout: .seconds(15))
        return ran.succeeded ? ran.stdout : ""
    }

    /// One test's details. The result bundle names a test with its `()`.
    public func details(of test: String) async -> String {
        await xcresulttool(["get", "test-results", "test-details", "--test-id", "\(test)()", "--path", path, "--compact"])
    }

    /// Every test the run ran, with its result: `xcresulttool get test-results tests`.
    public func tests() async -> String {
        await xcresulttool(["get", "test-results", "tests", "--path", path, "--compact"])
    }

    /// The run's skipped tests: MobileBuildMCP's list can leave one out.
    public func skips() async -> [(test: String, skip: Skip)] {
        Self.skippedTests(listing: await tests())
    }

    public func summary() async -> String {
        await xcresulttool(["get", "test-results", "summary", "--path", path, "--compact"])
    }

    /// A crash's summary, from the crash log the result bundle attached to the test.
    public func crash(of test: String) async -> [String]? {
        let folder = exportFolder()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = await xcresulttool(["export", "attachments", "--path", path, "--output-path", folder.path, "--test-id", "\(test)()", "--only-failures"])
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        guard let log = names.sorted().first(where: { $0.hasSuffix(".ips") }),
              let text = try? String(contentsOf: folder.appending(path: log), encoding: .utf8)
        else { return nil }
        return Self.crashSummary(log: text)
    }
}
