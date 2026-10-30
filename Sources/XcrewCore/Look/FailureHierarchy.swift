import Foundation

/// The app's accessibility hierarchy at a UI test's failure, kept whole where Claude can Read it, and read when its
/// shape is one xcrew knows.
struct FailureHierarchy: Sendable, Equatable {
    let text: String
    let hierarchy: UIHierarchy?
    let path: String

    /// How XCTest names the hierarchy it attaches, for one whose shape is no longer the one `UIHierarchy` reads.
    static let suggestedName = "App UI hierarchy"

    /// The hierarchy XCTest attached at `run`'s failure, among `attachments`, the test's in `export`'s manifest: the
    /// latest text attachment of the run's configuration and device, up to the failure, in a hierarchy's shape; or,
    /// when none has it, the latest one named as a hierarchy. Kept whole in `<run folder>/<suite>/<test>/`, numbered as
    /// the run's screen is. Nil when the run attached none, as when no query failed.
    static func keep(of test: TestID, run: FailedRun, number: Int?, attachments: [[String: Any]], from export: URL, in runFolder: URL) -> FailureHierarchy? {
        let texts = attachments.compactMap { attachment -> (name: String, text: String, at: Double)? in
            guard attachment["configurationName"] as? String == run.configuration, attachment["deviceId"] as? String == run.deviceID,
                  let exported = attachment["exportedFileName"] as? String, let at = attachment["timestamp"] as? Double, at <= run.failedAt,
                  let text = try? String(contentsOf: export.appending(path: exported), encoding: .utf8)
            else { return nil }
            return (attachment["suggestedHumanReadableName"] as? String ?? "", text, at)
        }.sorted { $0.at > $1.at }
        let shaped = texts.lazy.compactMap { found in UIHierarchy(text: found.text).map { (found.text, Optional($0)) } }.first
        guard let (text, hierarchy) = shaped ?? texts.first(where: { $0.name.hasPrefix(suggestedName) }).map({ ($0.text, UIHierarchy?.none) }) else { return nil }
        let kept = FailureImages.folder(of: test, in: runFolder)
        try? FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
        let name = (["hierarchy at failure", run.device, run.configuration] + (number.map { ["run \($0)"] } ?? [])).joined(separator: ", ").replacingOccurrences(of: "/", with: "-")
        let destination = kept.appending(path: "\(name).txt")
        try? text.write(to: destination, atomically: true, encoding: .utf8)
        return FailureHierarchy(text: text, hierarchy: hierarchy, path: destination.path)
    }
}
