import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The screen at a UI test's failure, kept where Claude can Read it: the last frame of the run's screen recording, which
/// XCTest stops at the failure, and how long before the failure that frame is.
struct FailureScreen: Sendable, Equatable {
    let path: String
    let secondsBefore: Double

    /// How XCTest names a recording, as exported and as suggested (docs/findings.md).
    static let recordingSuffix = ".mp4"
    /// What `look` asks an export for: the recordings.
    static let recordings = "*" + recordingSuffix

    /// The screen at `run`'s failure, from its recording among `attachments`, the test's in `export`'s manifest, kept in
    /// `<run folder>/<suite>/<test>/`, numbered when the test failed more than once on one device and configuration.
    /// Nil when the run kept no recording, or it couldn't be read.
    static func keep(of test: TestID, run: FailedRun, number: Int? = nil, attachments: [[String: Any]], from export: URL, in runFolder: URL) async -> FailureScreen? {
        // The run's own: the same configuration and device, started before the failure; the latest, when a test kept more.
        let recordings = attachments.compactMap { attachment -> (file: URL, started: Double)? in
            guard attachment["configurationName"] as? String == run.configuration, attachment["deviceId"] as? String == run.deviceID,
                  let exported = attachment["exportedFileName"] as? String, let started = attachment["timestamp"] as? Double, started <= run.failedAt
            else { return nil }
            let file = export.appending(path: exported)
            return isMovie(file) ? (file, started) : nil
        }
        guard let recording = recordings.max(by: { $0.started < $1.started }) else { return nil }
        let kept = FailureImages.folder(of: test, in: runFolder)
        try? FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
        let name = (["screen at failure", run.device, run.configuration] + (number.map { ["run \($0)"] } ?? [])).joined(separator: ", ").replacingOccurrences(of: "/", with: "-")
        let destination = kept.appending(path: "\(name).png")
        // A frame stays on screen until the next, and the recording until it stops: the gap is from the recording's end.
        guard let frame = await lastFrame(of: recording.file, to: destination) else { return nil }
        return FailureScreen(path: destination.path, secondsBefore: max(0, run.failedAt - recording.started - frame.length))
    }

    /// Whether a file's first bytes say it's an MPEG-4 or QuickTime movie: an `ftyp` box first. The exported file's own
    /// extension says nothing, as with images.
    static func isMovie(_ file: URL) -> Bool {
        FailureImages.head(of: file, bytes: 8).map { $0.count == 8 && Data($0.dropFirst(4)) == Data("ftyp".utf8) } ?? false
    }

    /// Writes a movie's last frame to `destination` as a PNG, and answers when in the movie that frame shows and the
    /// movie's length, in seconds; nil when either fails.
    static func lastFrame(of movie: URL, to destination: URL) async -> (shown: Double, length: Double)? {
        let asset = AVURLAsset(url: movie)
        guard let length = try? await asset.load(.duration), length.seconds > 0 else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // The frame showing just before the end, decoded exactly: with any tolerance it lands on the keyframe before.
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        guard let (frame, shown) = try? await generator.image(at: length - CMTime(value: 1, timescale: 1000)),
              let png = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(png, frame, nil)
        return CGImageDestinationFinalize(png) ? (shown.seconds, length.seconds) : nil
    }
}
