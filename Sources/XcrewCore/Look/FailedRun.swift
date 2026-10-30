import Foundation

/// One failed run of a UI test, from `xcresulttool get test-results activities`: the device and test-plan configuration
/// it ran on, the last steps before it failed, the failing step, and when that step started.
public struct FailedRun: Sendable, Equatable {
    /// The model and OS: `iPhone 18 Pro Max, iOS 27.2`.
    public let device: String
    public let configuration: String
    public let steps: [String]
    public let failure: String
    /// When the failing step started, as a UNIX timestamp, as attachments are stamped.
    public let failedAt: Double
    /// The device's id, which ties the run to its attachments in the export's manifest.
    let deviceID: String

    /// The steps shown before the failing one.
    static let mostSteps = 4

    /// Each run that failed, in the order the activities list them.
    static func runs(activities: String) -> [FailedRun] {
        let runs = (ResultBundle.parse(activities) as? [String: Any])?["testRuns"] as? [[String: Any]] ?? []
        return runs.compactMap { run in
            let steps = run["activities"] as? [[String: Any]] ?? []
            guard let failing = steps.firstIndex(where: { $0["isAssociatedWithFailure"] as? Bool == true }),
                  let failure = steps[failing]["title"] as? String
            else { return nil }
            let device = run["device"] as? [String: Any] ?? [:]
            let model = device["modelName"] as? String ?? device["deviceName"] as? String ?? "a device"
            let os = [(device["platform"] as? String).map { $0.replacing(" Simulator", with: "") }, device["osVersion"] as? String].compactMap(\.self).joined(separator: " ")
            return FailedRun(
                device: os.isEmpty ? model : "\(model), \(os)",
                configuration: (run["testPlanConfiguration"] as? [String: Any])?["configurationName"] as? String ?? "",
                steps: steps[..<failing].suffix(mostSteps).compactMap { $0["title"] as? String },
                failure: failure,
                failedAt: steps[failing]["startTime"] as? Double ?? 0,
                deviceID: device["deviceId"] as? String ?? ""
            )
        }
    }
}
