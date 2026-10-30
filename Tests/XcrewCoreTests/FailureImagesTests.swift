import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// A failed test's images: the attachments `xcresulttool export attachments` writes for it, kept under the CLI's cache
/// and named under the test, so Claude can Read them.
@Suite struct FailureImagesTests {
    static let bundle = "/runs/test_sim_1.xcresult"
    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13])
    static let failed = """
    🧪 Test

    Test Failures (1):

      ✗ CardTests / testCard(): failed - Snapshot does not match reference.
        /Users/dev/App/Tests/CardTests.swift:12

    ❌ 1 test failed, 0 passed, 0 skipped (⏱️ 3.1s)
    """

    /// One attachment as `manifest.json` lists it, and the bytes of its exported file.
    struct Attachment {
        let suggested: String
        let exported: String
        let bytes: Data
    }

    /// A cache folder, and an export folder holding what xcresulttool would write for `CardTests/testCard()`.
    static func export(_ attachments: [Attachment], test: String = "CardTests/testCard()") throws -> (cache: URL, bundle: ResultBundle, images: URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "xcrew-tests-\(UUID().uuidString)")
        let export = root.appending(path: "export")
        try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
        for attachment in attachments { try attachment.bytes.write(to: export.appending(path: attachment.exported)) }
        let listed = attachments.map { #"{"exportedFileName":"\#($0.exported)","isAssociatedWithFailure":false,"suggestedHumanReadableName":"\#($0.suggested)"}"# }
        try Data(#"[{"attachments":[\#(listed.joined(separator: ","))],"testIdentifier":"\#(test)"}]"#.utf8).write(to: export.appending(path: "manifest.json"))
        let cache = root.appending(path: "cache")
        let runner = FakeRunner(responses: [
            "xcrun xcresulttool export attachments --path \(bundle) --output-path \(export.path) --test-id \(test)": .init(status: 0),
        ])
        return (cache, ResultBundle(path: bundle, runner: runner, exportFolder: { export }), cache.appending(path: "images"))
    }

    static func kept(_ cache: URL, _ name: String) -> String {
        cache.appending(path: "images/test_sim_1/CardTests/testCard/\(name)").path
    }

    @Test func aFailedTestsImagesAreListedReferenceThenFailureThenDifference() async throws {
        // Swift Testing numbers each image 0, in no set order; the exported names carry no extension.
        let (cache, bundle, images) = try Self.export([
            Attachment(suggested: "difference_0_D.png", exported: "D", bytes: Self.png),
            Attachment(suggested: "failure_0_F.png", exported: "F", bytes: Self.png),
            Attachment(suggested: "reference_0_R.png", exported: "R", bytes: Self.png),
            Attachment(suggested: "Complete Issue Description.txt", exported: "I.txt", bytes: Data("Snapshot does not match".utf8)),
        ])
        let added = await FailureNotes.addingText(to: Self.failed, from: bundle, keepingImagesIn: images)
        #expect(added.contains("""
              ✗ CardTests / testCard(): failed - Snapshot does not match reference.
                /Users/dev/App/Tests/CardTests.swift:12
                  image: \(Self.kept(cache, "reference_0_R.png"))
                  image: \(Self.kept(cache, "failure_0_F.png"))
                  image: \(Self.kept(cache, "difference_0_D.png"))

            """), "\(added)")
        #expect(FileManager.default.contents(atPath: Self.kept(cache, "difference_0_D.png")) == Self.png)
        #expect(!added.contains("Complete Issue Description"))
    }

    @Test func iOSSnapshotTestCaseNamesSortTheSameWay() async throws {
        let (cache, bundle, images) = try Self.export([
            Attachment(suggested: "Diffed Image_2_U.png", exported: "3.png", bytes: Self.png),
            Attachment(suggested: "Reference Image_0_U.png", exported: "1.png", bytes: Self.png),
            Attachment(suggested: "Failed Image_1_U.png", exported: "2.png", bytes: Self.png),
        ])
        let added = await FailureNotes.addingText(to: Self.failed, from: bundle, keepingImagesIn: images)
        let listed = added.components(separatedBy: "\n").filter { $0.contains("image: ") }
        #expect(listed == ["Reference Image_0_U.png", "Failed Image_1_U.png", "Diffed Image_2_U.png"].map { "      image: \(Self.kept(cache, $0))" })
    }

    /// The suggested name or the file's content says it's an image; the exported file's extension never does.
    @Test func anImageIsKnownByItsNameOrContentNeverItsExportedExtension() async throws {
        let (cache, bundle, images) = try Self.export([
            Attachment(suggested: "screen", exported: "A", bytes: Self.png),
            Attachment(suggested: "photo.jpg", exported: "B", bytes: Data("not a JPEG's bytes".utf8)),
            Attachment(suggested: "log.txt", exported: "C.png", bytes: Data("plain text".utf8)),
        ])
        let added = await FailureNotes.addingText(to: Self.failed, from: bundle, keepingImagesIn: images)
        let listed = added.components(separatedBy: "\n").filter { $0.contains("image: ") }
        // One with no extension in its name gets the one its content says, so Read opens it as an image. Images that
        // are neither reference, failure nor difference keep the order they were attached in.
        #expect(listed == ["      image: \(Self.kept(cache, "screen.png"))", "      image: \(Self.kept(cache, "photo.jpg"))"], "\(added)")
    }

    @Test func pastThreeImagesTheRestAreCountedWithTheirFolder() async throws {
        let (cache, bundle, images) = try Self.export((1...5).map { Attachment(suggested: "Screenshot \($0).png", exported: "\($0)", bytes: Self.png) })
        let added = await FailureNotes.addingText(to: Self.failed, from: bundle, keepingImagesIn: images)
        #expect(added.components(separatedBy: "\n").count { $0.contains("image: ") } == 3)
        #expect(added.contains("      and 2 more images in \(cache.appending(path: "images/test_sim_1/CardTests/testCard").path)\n"), "\(added)")
    }

    @Test func aFailureWithoutImagesAddsNothing() async throws {
        let (_, bundle, images) = try Self.export([Attachment(suggested: "Complete Issue Description.txt", exported: "I.txt", bytes: Data("failed".utf8))])
        #expect(await FailureNotes.addingText(to: Self.failed, from: bundle, keepingImagesIn: images) == Self.failed)
    }

    /// A bundle's images are kept as long as the CLI keeps an unused build, then go with the next lookup.
    @Test func imagesOlderThanTheCLIKeepsABuildAreRemoved() async throws {
        let (cache, bundle, images) = try Self.export([Attachment(suggested: "reference_0_R.png", exported: "R", bytes: Self.png)])
        let old = images.appending(path: "old_run"), fresh = images.appending(path: "fresh_run")
        for folder in [old, fresh] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-15 * 24 * 3600)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-13 * 24 * 3600)], ofItemAtPath: fresh.path)
        _ = await FailureNotes.addingText(to: Self.failed, from: bundle, keepingImagesIn: images)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(FileManager.default.fileExists(atPath: Self.kept(cache, "reference_0_R.png")))
    }

    /// A crashed test's images and crash log come from one export: every attachment holds the crash log too.
    @Test func aCrashedTestsImagesAndCrashLogComeFromOneExport() async throws {
        let (cache, bundle, images) = try Self.export([Attachment(suggested: "Screenshot.png", exported: "S", bytes: Self.png)], test: "FormatterTests/test_crash()")
        let export = bundle.exportFolder().path
        try Captured.text("crashLog").write(toFile: export + "/crash.ips", atomically: true, encoding: .utf8)
        let added = await FailureNotes.addingText(to: Captured.text("mobileTestsCrashedAndSkipped"), from: bundle, keepingImagesIn: images)
        #expect(added.contains("Crash: xctest at implicit closure #1 in FormatterTests.test_crash()\n      crashed: EXC_BREAKPOINT (SIGTRAP)"), "\(added)")
        #expect(added.contains("      image: \(cache.appending(path: "images/test_sim_1/FormatterTests/test_crash/Screenshot.png").path)"), "\(added)")
    }

    /// The failures pane shows the same paths under the test.
    @Test func theFailureCarriesItsImagesForThePane() async throws {
        let (cache, bundle, images) = try Self.export((1...4).map { Attachment(suggested: "Screenshot \($0).png", exported: "\($0)", bytes: Self.png) })
        let added = try #require(await FailureNotes.adding(to: MobileText(Self.failed), from: bundle, keepingImagesIn: images))
        let failures = Report.attaching(added.images, to: ToolOutput(added.text, isError: false).failures)
        let withImages = try #require(failures.first)
        #expect(withImages.images == (1...3).map { Self.kept(cache, "Screenshot \($0).png") })
        #expect(withImages.moreImages == "and 1 more image in \(cache.appending(path: "images/test_sim_1/CardTests/testCard").path)")
    }
}
