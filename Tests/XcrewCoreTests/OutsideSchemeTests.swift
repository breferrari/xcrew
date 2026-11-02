import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// A test run whose `-only-testing:` names a target its scheme doesn't test: Xcode refuses it with "Tests in the target
/// “X” can’t be run because “X” isn’t a member of the specified test plan or scheme." (Xcode 27.2's XCTHarness). Field
/// shape, names neutralised: a module's test target asked for under the `unit` profile's scheme, which doesn't test it.
/// Composed from the test bed's `empty-filter` capture, whose log names the scheme `Feature`, with that error added.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct OutsideSchemeTests {
    static let refusal = "Tests in the target “CoreTests” can’t be run because “CoreTests” isn’t a member of the specified test plan or scheme."

    /// `empty-filter`'s JSON, failed with Xcode's refusal as its error.
    static func json(refusals: [String] = [refusal]) throws -> String {
        var structured = try #require(try Raw.capture("empty-filter")["structuredContent"] as? [String: Any])
        var data = try #require(structured["data"] as? [String: Any])
        var diagnostics = try #require(data["diagnostics"] as? [String: Any])
        diagnostics["errors"] = refusals.map { ["message": $0] }
        data["diagnostics"] = diagnostics
        structured["data"] = data
        return String(decoding: try JSONSerialization.data(withJSONObject: structured, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }

    /// A project whose `Feature` scheme tests `FeatureTests` and whose `Core` and `Everything` schemes test `CoreTests`,
    /// and a home holding the capture's log where the result names it.
    static func setting(log: Bool = true, coreSchemes: Bool = true) throws -> (project: Project, home: String) {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        project.writePBXProj(["FeatureTests": "bundle.unit-test", "CoreTests": "bundle.unit-test"])
        project.writeScheme("Feature", testing: ["FeatureTests"])
        if coreSchemes {
            project.writeScheme("Everything", testing: ["FeatureTests", "CoreTests"])
            project.writeScheme("Core", testing: ["CoreTests"])
        }
        let home = project.root.appending(path: "home")
        if log {
            let path = try #require(ToolOutput(text: try json(), server: .mobileBuildMCP).buildLog(home: home.path))
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
            try Raw.file("empty-filter.log").write(toFile: path, atomically: true, encoding: .utf8)
        }
        return (project, home.path)
    }

    static func notes(log: Bool = true, coreSchemes: Bool = true, kind: Report.Kind = .test) async throws -> [String] {
        let (project, home) = try setting(log: log, coreSchemes: coreSchemes)
        let output = ToolOutput(text: try json(), server: .mobileBuildMCP, isError: true)
        return await Report.make(kind: kind, output: output, home: home, runner: FakeRunner(), project: project).notes
    }

    /// The note names the run's scheme, the narrowest scheme that tests the target, and the call that switches to it.
    @Test func aTargetOutsideTheRunsSchemeNamesASchemeThatTestsIt() async throws {
        let notes = try await Self.notes()
        #expect(notes == [#"xcrew: the Feature scheme doesn't test CoreTests, the target `-only-testing:` names, so Xcode ran none. The Core scheme tests it: `session_set_defaults {"scheme":"Core"}` makes Core the active profile's scheme."#], "\(notes)")
    }

    /// With no log to name the run's scheme, the note says this run's.
    @Test func withNoLogTheNoteSaysThisRunsScheme() async throws {
        #expect(try await Self.notes(log: false).contains(#"xcrew: this run's scheme doesn't test CoreTests, the target `-only-testing:` names, so Xcode ran none. The Core scheme tests it: `session_set_defaults {"scheme":"Core"}` makes Core the active profile's scheme."#))
    }

    /// No shared scheme runs the target by default, as far as xcrew can read: the note says so, and offers no call.
    @Test func noSchemeTestingTheTargetIsSaid() async throws {
        #expect(try await Self.notes(coreSchemes: false).contains("xcrew: the Feature scheme doesn't test CoreTests, the target `-only-testing:` names, so Xcode ran none. xcrew found no shared scheme that runs it by default."))
    }

    /// The scheme Xcode refused is never the one named, though a test plan it doesn't run by default lists the target.
    @Test func theRefusedSchemeIsNeverTheOneNamed() async throws {
        let (project, home) = try Self.setting(coreSchemes: false)
        project.writePBXProj(["FeatureTests": "bundle.unit-test", "CoreTests": "bundle.unit-test", "DataTests": "bundle.unit-test", "KitTests": "bundle.unit-test"])
        project.write(#"{"testTargets":[{"target":{"containerPath":"container:App.xcodeproj","name":"CoreTests"}}],"version":1}"#, to: "Extra.xctestplan")
        project.write(#"<?xml version="1.0" encoding="UTF-8"?><Scheme><TestAction><TestPlans><TestPlanReference default = "YES" reference = "container:Feature.xctestplan"></TestPlanReference><TestPlanReference reference = "container:Extra.xctestplan"></TestPlanReference></TestPlans></TestAction></Scheme>"#, to: "App.xcodeproj/xcshareddata/xcschemes/Feature.xcscheme")
        project.write(#"{"testTargets":[{"target":{"containerPath":"container:App.xcodeproj","name":"FeatureTests"}}],"version":1}"#, to: "Feature.xctestplan")
        project.writeScheme("Core", testing: ["CoreTests", "DataTests", "KitTests"])
        let output = ToolOutput(text: try Self.json(), server: .mobileBuildMCP, isError: true)
        let notes = await Report.make(kind: .test, output: output, home: home, runner: FakeRunner(), project: project).notes
        #expect(notes.contains { $0.contains(#"The Core scheme tests it: `session_set_defaults {"scheme":"Core"}`"#) }, "\(notes)")
    }

    /// The selected Xcode's XCTHarness still words the refusal in the pieces the note reads, the target's name between
    /// them: a change in its wording turns this red.
    @Test(.enabled(if: (Version.major(of: HookTests.installedXcode?.version ?? "") ?? 0) >= 27, "no Xcode 27 or later selected"))
    func theSelectedXcodeWordsTheRefusalAsTheNoteReadsIt() throws {
        let xcode = try #require(HookTests.installedXcode)
        let harness = try Data(contentsOf: URL(fileURLWithPath: xcode.path).appending(path: "Contents/SharedFrameworks/XCTHarness.framework/XCTHarness"))
        let pieces = ["Tests in the target “", "” can’t be run because “", "” isn’t a member of the specified test plan or scheme."]
        for piece in pieces { #expect(harness.range(of: Data(piece.utf8)) != nil, "\(xcode.path) no longer says \(piece)") }
        #expect(OutsideScheme.targets(in: pieces[0] + "CoreTests" + pieces[1] + "CoreTests" + pieces[2]) == ["CoreTests"])
    }

    /// A scheme that lists the target only in a test plan it doesn't run by default would be refused the same way.
    @Test func aSchemeWhoseDefaultPlanLeavesTheTargetOutIsntNamed() async throws {
        let (project, home) = try Self.setting(coreSchemes: false)
        project.write(#"{"testTargets":[{"target":{"containerPath":"container:App.xcodeproj","name":"FeatureTests"}}],"version":1}"#, to: "Smoke.xctestplan")
        project.write(#"{"testTargets":[{"target":{"containerPath":"container:App.xcodeproj","name":"CoreTests"}}],"version":1}"#, to: "Extra.xctestplan")
        project.write(#"<?xml version="1.0" encoding="UTF-8"?><Scheme><TestAction><TestPlans><TestPlanReference default = "YES" reference = "container:Smoke.xctestplan"></TestPlanReference><TestPlanReference reference = "container:Extra.xctestplan"></TestPlanReference></TestPlans></TestAction></Scheme>"#, to: "App.xcodeproj/xcshareddata/xcschemes/Another.xcscheme")
        project.writeScheme("Core", testing: ["CoreTests", "FeatureTests"])
        let output = ToolOutput(text: try Self.json(), server: .mobileBuildMCP, isError: true)
        let notes = await Report.make(kind: .test, output: output, home: home, runner: FakeRunner(), project: project).notes
        #expect(notes.contains { $0.contains(#"The Core scheme tests it: `session_set_defaults {"scheme":"Core"}`"#) }, "\(notes)")
    }

    /// Every target refused is named, and the scheme named tests them all.
    @Test func severalRefusedTargetsAreNamedWithASchemeThatTestsThemAll() async throws {
        let (project, home) = try Self.setting()
        let refusals = [Self.refusal, Self.refusal.replacing("CoreTests", with: "FeatureTests")]
        let output = ToolOutput(text: try Self.json(refusals: refusals), server: .mobileBuildMCP, isError: true)
        let notes = await Report.make(kind: .test, output: output, home: home, runner: FakeRunner(), project: project).notes
        #expect(notes.contains(#"xcrew: the Feature scheme doesn't test CoreTests and FeatureTests, the targets `-only-testing:` names, so Xcode ran none. The Everything scheme tests them: `session_set_defaults {"scheme":"Everything"}` makes Everything the active profile's scheme."#), "\(notes)")
    }

    /// The call is MobileBuildMCP's: the Xcode MCP's result gets no note naming it.
    @Test func anXcodeMCPResultAddsNoNote() async throws {
        let (project, home) = try Self.setting()
        let output = ToolOutput(text: Self.refusal, server: .xcode, isError: true)
        let notes = await Report.make(kind: .test, output: output, home: home, runner: FakeRunner(), project: project).notes
        #expect(!notes.contains { $0.contains("session_set_defaults") }, "\(notes)")
    }

    /// A build's result says nothing of it.
    @Test func aBuildAddsNoNote() async throws {
        #expect(try await !Self.notes(kind: .build).contains { $0.contains("-only-testing:") })
    }
}
