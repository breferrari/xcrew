import CryptoKit
import Foundation

public enum ConfigWriter {
    public enum Outcome: Equatable, Sendable {
        case written(backup: URL?)
        /// A config xcrew didn't write was found and left as it was.
        case keptUnmanaged
        /// xcrew wrote it, but someone has edited it since; left as it was.
        case keptEdited
    }

    /// Writes the config unless one exists that xcrew didn't write, or that was edited after xcrew
    /// wrote it; `force` replaces either, keeping a timestamped backup beside it.
    public static func write(
        _ answers: ProfileAnswers,
        to project: Project,
        simulatorIDs: [String: String] = [:],
        force: Bool = false,
        now: Date = Date()
    ) throws -> Outcome {
        let fileManager = FileManager.default
        let config = project.mobileBuildMCPConfig
        let existing = try? Data(contentsOf: config)
        let marker = try? Data(contentsOf: project.managedMarker)

        let kept: Outcome? = switch (existing, marker) {
        case (nil, _): nil
        case (_, nil): .keptUnmanaged
        // Markers from before the fingerprint were empty: still xcrew's, still updated.
        case (let content?, let fingerprint?): fingerprint.isEmpty || fingerprint == Self.fingerprint(content) ? nil : .keptEdited
        }
        if let kept, !force { return kept }

        var backup: URL?
        if kept != nil {
            let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "")
            backup = config.appendingPathExtension("backup-\(stamp)")
            try fileManager.copyItem(at: config, to: backup!)
        }
        let content = Data(ConfigRenderer.render(answers, root: project.root, simulatorIDs: simulatorIDs).utf8)
        try fileManager.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: config, options: .atomic)
        try Self.fingerprint(content).write(to: project.managedMarker, options: .atomic)
        return .written(backup: backup)
    }

    /// What the marker holds: a hash of the config exactly as xcrew wrote it.
    static func fingerprint(_ content: Data) -> Data {
        Data(SHA256.hash(data: content).map { byte in
            let hex = String(byte, radix: 16)
            return hex.count == 1 ? "0" + hex : hex
        }.joined().utf8)
    }
}
