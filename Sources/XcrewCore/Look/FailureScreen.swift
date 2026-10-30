import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The screen at a UI test's failure, kept where Claude can Read it: the last frame of the run's screen recording, which
/// XCTest stops at the failure, and how long before the failure that frame is.
public struct FailureScreen: Sendable, Equatable {
    public let path: String
    public let secondsBefore: Double

    /// The screen at `run`'s failure, from its recording among `test`'s exported attachments, kept in
    /// `<folder>/<suite>/<test>/`. Nil when the run kept no recording, or it couldn't be read.
    static func keep(of test: TestID, run: FailedRun, from export: URL, in folder: URL) async -> FailureScreen? {
        let manifest = (try? JSONSerialization.jsonObject(with: Data(contentsOf: export.appending(path: "manifest.json")))) as? [[String: Any]] ?? []
        let attachments = manifest.filter { ($0["testIdentifier"] as? String).map(TestID.init(xcresultID:)) == test }.flatMap { $0["attachments"] as? [[String: Any]] ?? [] }
        // The run's own: the same configuration and device, started before the failure; the latest, when a test kept more.
        let recordings = attachments.compactMap { attachment -> (file: URL, started: Double)? in
            guard attachment["configurationName"] as? String == run.configuration, attachment["deviceId"] as? String == run.deviceID,
                  let exported = attachment["exportedFileName"] as? String, let started = attachment["timestamp"] as? Double, started <= run.failedAt
            else { return nil }
            let file = export.appending(path: exported)
            return isMovie(file) ? (file, started) : nil
        }
        guard let recording = recordings.max(by: { $0.started < $1.started }) else { return nil }
        let kept = [test.suite, test.name].reduce(folder) { $0.appending(path: $1.replacingOccurrences(of: "/", with: "-")) }
        try? FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
        let name = "screen at failure, \(run.device), \(run.configuration)".replacingOccurrences(of: "/", with: "-")
        let destination = kept.appending(path: "\(name).png")
        // A frame stays on screen until the next, and the recording until it stops: the gap is from the recording's end.
        guard let frame = await lastFrame(of: recording.file, to: destination) else { return nil }
        return FailureScreen(path: destination.path, secondsBefore: max(0, run.failedAt - recording.started - frame.length))
    }

    /// Whether a file's first bytes say it's an MPEG-4 or QuickTime movie: an `ftyp` box first. The exported file's own
    /// extension says nothing, as with images.
    static func isMovie(_ file: URL) -> Bool {
        let head = (try? FileHandle(forReadingFrom: file)).flatMap { handle in
            defer { try? handle.close() }
            return try? handle.read(upToCount: 8)
        }
        return head.map { $0.count == 8 && Data($0.dropFirst(4)) == Data("ftyp".utf8) } ?? false
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
