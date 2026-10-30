import Foundation

/// One failed run of a UI test, from `xcresulttool get test-results activities`: the device and test-plan configuration
/// it ran on, the last steps before it failed, the failing step, and when that step started.
struct FailedRun: Sendable, Equatable {
    /// The model and OS: `iPhone 18 Pro Max, iOS 27.2`.
    let device: String
    let configuration: String
    let steps: [String]
    let failure: String
    /// When the failing step started, as a UNIX timestamp, as attachments are stamped.
    let failedAt: Double
    /// The device's id, which ties the run to its attachments in the export's manifest.
    let deviceID: String
    /// Whether the run kept a screen recording, as a UI test's failed run does.
    var hasRecording = false

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
                hasRecording: ResultBundle.nodes(steps).contains { ($0["name"] as? String)?.hasSuffix(FailureScreen.recordingSuffix) == true }
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
}
