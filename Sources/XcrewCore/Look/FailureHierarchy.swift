import Foundation

/// The app's accessibility hierarchy at a UI test's failure, kept whole where Claude can Read it, and read when its
/// shape is one xcrew knows.
struct FailureHierarchy: Sendable, Equatable {
    enum Content: Sendable, Equatable {
        /// In the shape `UIHierarchy` reads.
        case read(UIHierarchy)
        /// In another shape, as XCTest wrote it.
        case asWritten(String)
    }

    let content: Content
    let path: String

    /// How XCTest names the hierarchy it attaches, for one whose shape is no longer the one `UIHierarchy` reads.
    static let suggestedName = "App UI hierarchy"

    /// The hierarchy XCTest attached to `run`, among the run's own attachments in an export, whose files `files` names
    /// by attachment id: the latest text one in a hierarchy's shape, or, when none has it, the latest one named as a
    /// hierarchy. Kept whole in `<run folder>/<suite>/<test>/`, numbered as the run's screen is. Nil when the run
    /// attached none, as when no query failed, or it couldn't be kept.
    static func keep(of test: TestID, run: FailedRun, number: Int?, files: [String: URL], in runFolder: URL) -> FailureHierarchy? {
        // Text only: a recording or an image is read no further than its first bytes.
        let texts = run.attachments.sorted { $0.at > $1.at }.compactMap { attachment -> (name: String, text: String)? in
            guard let file = files[attachment.id], !FailureScreen.isMovie(file), FailureImages.head(of: file, bytes: 12).flatMap(FailureImages.format(of:)) == nil,
                  let text = try? String(contentsOf: file, encoding: .utf8)
            else { return nil }
            return (attachment.name, text)
        }
        let shaped = texts.lazy.compactMap { found in UIHierarchy(text: found.text).map { (found.text, Content.read($0)) } }.first
        guard let (text, content) = shaped ?? texts.first(where: { $0.name.hasPrefix(suggestedName) }).map({ ($0.text, Content.asWritten($0.text)) }) else { return nil }
        let destination = run.keptFile("hierarchy at failure", extension: "txt", number: number, of: test, in: runFolder)
        guard (try? text.write(to: destination, atomically: true, encoding: .utf8)) != nil else { return nil }
        return FailureHierarchy(content: content, path: destination.path)
    }
}
