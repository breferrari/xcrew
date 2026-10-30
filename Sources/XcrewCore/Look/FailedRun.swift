import Foundation

/// One failed run of a UI test, from `xcresulttool get test-results activities`: the device and test-plan configuration
/// it ran on, the last steps before it failed, the failing step, when that step started, and the run's own attachments.
struct FailedRun: Sendable, Equatable {
    /// One of a run's attachments: its name as XCTest gave it, and its id, which names its file in an export.
    struct Attachment: Sendable, Equatable {
        let name: String
        let id: String
        let at: Double
    }

    /// The model and OS: `iPhone 18 Pro Max, iOS 27.2`.
    let device: String
    let configuration: String
    let steps: [String]
    let failure: String
    /// When the failing step started, as a UNIX timestamp, as attachments are stamped.
    let failedAt: Double
    /// The device's id: with the configuration, which runs of a test ran alike.
    let deviceID: String
    /// The run's own attachments, from every step of it, each once, in the order listed.
    let attachments: [Attachment]

    /// Whether the run kept a screen recording, as a UI test's failed run does.
    var hasRecording: Bool { attachments.contains { $0.name.hasSuffix(FailureScreen.recordingSuffix) } }

    /// The steps shown before the failing one.
    static let mostSteps = 4

    /// Each run that failed, in the order the activities list them; nil when they can't be read, as when
    /// `xcresulttool` gave no answer.
    static func runs(activities: String) -> [FailedRun]? {
        guard let runs = (ResultBundle.parse(activities) as? [String: Any])?["testRuns"] as? [[String: Any]] else { return nil }
        return runs.compactMap { run in
            let steps = run["activities"] as? [[String: Any]] ?? []
            // The top-level step the failure is in: the failing step itself, or one of the test's own holding it, which
            // then leads up to it too.
            guard let failing = steps.firstIndex(where: { failure(in: $0) != nil }) else { return nil }
            let inside = (steps[failing]["childActivities"] as? [[String: Any]] ?? []).lazy.compactMap(failure(in:)).first
            let failed = inside ?? steps[failing]
            guard let title = failed["title"] as? String else { return nil }
            let leading = steps[..<failing] + (inside == nil ? [] : [steps[failing]])
            let device = run["device"] as? [String: Any] ?? [:]
            let model = device["modelName"] as? String ?? device["deviceName"] as? String ?? "a device"
            let os = [(device["platform"] as? String).map { $0.replacing(" Simulator", with: "") }, device["osVersion"] as? String].compactMap(\.self).joined(separator: " ")
            return FailedRun(
                device: os.isEmpty ? model : "\(model), \(os)",
                configuration: (run["testPlanConfiguration"] as? [String: Any])?["configurationName"] as? String ?? "",
                steps: leading.suffix(mostSteps).compactMap { $0["title"] as? String },
                failure: title,
                failedAt: failed["startTime"] as? Double ?? 0,
                deviceID: device["deviceId"] as? String ?? "",
                attachments: attachments(of: steps)
            )
        }
    }

    /// The step a failure is marked on, in `step` or below it: the deepest marked one, where XCTest records it.
    static func failure(in step: [String: Any]) -> [String: Any]? {
        for child in step["childActivities"] as? [[String: Any]] ?? [] {
            if let found = failure(in: child) { return found }
        }
        return step["isAssociatedWithFailure"] as? Bool == true ? step : nil
    }

    /// The attachments of `steps` and every step below them, each once: XCTest lists one under each step it belongs to.
    static func attachments(of steps: [[String: Any]]) -> [Attachment] {
        var seen: Set<String> = []
        var found: [Attachment] = []
        func walk(_ steps: [[String: Any]]) {
            for step in steps {
                for attachment in step["attachments"] as? [[String: Any]] ?? [] {
                    guard let name = attachment["name"] as? String, let id = attachment["uuid"] as? String, seen.insert(id).inserted else { continue }
                    found.append(Attachment(name: name, id: id, at: attachment["timestamp"] as? Double ?? 0))
                }
                walk(step["childActivities"] as? [[String: Any]] ?? [])
            }
        }
        walk(steps)
        return found
    }

    /// Where a file kept for this run goes: `<run folder>/<suite>/<test>/<what>, <device>, <configuration>[, run n].<ext>`,
    /// its folder made.
    func keptFile(_ what: String, extension ext: String, number: Int?, of test: TestID, in runFolder: URL) -> URL {
        let folder = FailureImages.folder(of: test, in: runFolder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = ([what, device, configuration] + (number.map { ["run \($0)"] } ?? [])).joined(separator: ", ").replacingOccurrences(of: "/", with: "-")
        return folder.appending(path: "\(name).\(ext)")
    }
}
