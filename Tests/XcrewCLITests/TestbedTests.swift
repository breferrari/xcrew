import Foundation
import Testing
@testable import XcrewCLI
@testable import XcrewCore
import XcrewTestSupport

/// The test bed's fixtures (breferrari/xcrew-testbed): one app as each project form, at the root and under `ios/`, and
/// projects shaped to trip xcrew up. Each is checked against its own `expect.xcrew.json` on a copy, as a repository of
/// its own, with no build. CI checks the test bed out at a pinned commit and names it in `XCREW_TESTBED`; on a Mac,
/// a clone beside this repository's is the default, and without one the suite is skipped.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed: clone breferrari/xcrew-testbed beside this repository, or set XCREW_TESTBED"))
struct TestbedTests {
    static let testbed = Testbed.root
    static let forms = testbed.appending(path: "forms")

    static func names(in folder: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: testbed.appending(path: folder).path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

    static var names: [String] { names(in: "forms") }
    /// Projects shaped to trip xcrew up: a `Project.swift` source file, and the old macro copy phase in the JSON format.
    static var adversarial: [String] { names(in: "adversarial") }

    /// What `expect.xcrew.json` states, and what the checks below find.
    struct Outcome: Codable, Hashable {
        var isApplePlatformProject: Bool
        var generator: String?
        var generatorRoot: String?
        var isGenerated: Bool
        var container: String?
        /// Words the reason setup gives when it finds no container must contain.
        var containerProblem: String?
        var profiles: [String]
        var activeProfile: String?
        var testScheme: String?
        var doctor: [String: String]
    }

    static let simulators = FakeRunner(responses: [
        "xcrun simctl list devices available --json": .init(status: 0, stdout: #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone 18","udid":"U18","isAvailable":true}]}}"#),
    ])

    /// A copy of the fixture with a `.git` of its own, so its root is a repository's; setup writes into it.
    static func copy(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "xcrew-testbed-\(UUID().uuidString)/\(URL(fileURLWithPath: name).lastPathComponent)")
        try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: testbed.appending(path: name), to: root)
        try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
        return root
    }

    /// What xcrew finds in the fixture, with the reason setup gives in full when it finds no container.
    static func outcome(of name: String) async throws -> Outcome {
        let root = try copy(name)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        // The machine's home is the one `CheckContext.fake` gives it, so the search leaves out the same folder.
        let project = Project(root: root, home: root.appending(path: "home"))
        let context = CheckContext.fake(simulators, project: project)
        let manifests = project.layout(.anywhereButHome).generator
        let answer = try JSONDecoder().decode(ProjectCommand.Answer.self, from: Data(await Run("project", "--setup", context: context).text.utf8))
        _ = await Run("setup", "--test-simulator", "iPhone 18", "--app-scheme", "App", context: context)
        let config = (try? String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8)) ?? ""
        let profiles = ConfigRenderer.profiles(in: config)
        let doctor = await Doctor.run([ProjectConfigCheck(), MacroCopyPhaseCheck()], in: context)
        return Outcome(
            isApplePlatformProject: project.isApplePlatformProject,
            generator: manifests.map { $0.generator == .tuist ? "tuist" : "xcodegen" },
            generatorRoot: manifests.map { $0.path.isEmpty ? "." : $0.path },
            isGenerated: answer.isGenerated,
            container: answer.container,
            containerProblem: answer.containerProblem,
            profiles: profiles.names,
            activeProfile: profiles.active,
            testScheme: scheme(of: "unit", in: config),
            doctor: Dictionary(uniqueKeysWithValues: doctor.map { ($0.check.id, "\($0.result.status)") })
        )
    }

    /// The `scheme:` of one profile in a config setup wrote.
    static func scheme(of profile: String, in config: String) -> String? {
        let lines = config.split(whereSeparator: \.isNewline).map(String.init)
        guard let start = lines.firstIndex(of: "  \(profile):") else { return nil }
        return lines[(start + 1)...].prefix { $0.hasPrefix("    ") }
            .compactMap { $0.firstMatch(of: /^\s+scheme: ["']?([^"']+)["']?$/).map { String($0.1) } }.first
    }

    /// `name` is the fixture's path in the test bed, as in `forms/classic`.
    static func expected(_ name: String) throws -> Outcome {
        try JSONDecoder().decode(Outcome.self, from: Data(contentsOf: testbed.appending(path: "\(name)/expect.xcrew.json")))
    }

    @Test func everyFormIsHere() {
        #expect(Self.names == ["classic", "classic-ios", "folders", "folders-ios", "json", "json-ios", "tuist", "tuist-ios", "tuist-ungenerated", "tuist-ungenerated-ios", "xcodegen", "xcodegen-ios"])
    }

    @Test(arguments: names.map { "forms/\($0)" } + adversarial.map { "adversarial/\($0)" })
    func eachFixtureIsWhatItsExpectationSays(_ name: String) async throws {
        let expected = try Self.expected(name)
        var actual = try await Self.outcome(of: name)
        if let problem = expected.containerProblem {
            #expect(actual.containerProblem?.contains(problem) == true, "setup said \(actual.containerProblem ?? "nothing")")
            actual.containerProblem = problem
        }
        #expect(actual == expected, "found \(actual)")
    }

    /// An edit to each file, and the command that regenerates the project after it: none for a file no generator reads.
    static let edits: [(file: String, generate: String?)] = [
        ("forms/tuist/Project.swift", "tuist generate --no-open"),
        ("forms/tuist/Tuist.swift", "tuist generate --no-open"),
        ("forms/tuist/App/ContentView.swift", nil),
        ("forms/tuist-ios/ios/Project.swift", "tuist generate --no-open --path ios"),
        ("forms/tuist-ungenerated-ios/ios/Project.swift", "tuist generate --no-open --path ios"),
        ("forms/xcodegen/project.yml", "xcodegen generate"),
        ("forms/xcodegen-ios/ios/project.yml", "xcodegen generate --spec ios/project.yml"),
        ("forms/classic/App/ContentView.swift", nil),
        ("adversarial/project-swift-trap/App/Models/Project.swift", nil),
    ]

    @Test(arguments: edits.map(\.file))
    func anEditNamesTheCommandThatRegenerates(_ file: String) async throws {
        let fixture = file.split(separator: "/").prefix(2).joined(separator: "/")
        let root = try Self.copy(fixture)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let edited = root.appending(path: String(file.dropFirst(fixture.count + 1)))
        #expect(FileManager.default.fileExists(atPath: edited.path), "the test bed has no \(file)")
        let context = CheckContext.fake(project: Project(root: root, home: root.appending(path: "home")))
        let answer = try JSONDecoder().decode(ProjectCommand.Answer.self, from: Data(await Run("project", "--manifest", edited.path, context: context).text.utf8))
        #expect(answer.generate == Self.edits.first { $0.file == file }?.generate)
    }

    /// The forms hold one app, so they differ only where a form must: its generator, and where the project sits.
    @Test func theFormsDifferOnlyInTheirGeneratorAndPlace() throws {
        let built = try Self.names.filter { !$0.hasPrefix("tuist-ungenerated") }.map { name in
            var outcome = try Self.expected("forms/\(name)")
            (outcome.generator, outcome.generatorRoot, outcome.isGenerated) = (nil, nil, false)
            outcome.container = outcome.container.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
            return outcome
        }
        #expect(Set(built).count == 1, "\(Set(built))")
    }

    /// Every file of a JSON form's folders is in its target: `xcodeproj` records them all as exclusions when phases come
    /// after the folder (docs/findings.md, *Making the test bed's projects*).
    @Test func theJSONFormsExcludeNothing() throws {
        for name in Self.names where name.hasPrefix("json") {
            let container = try #require(try Self.expected("forms/\(name)").container)
            let project = try String(contentsOf: Self.forms.appending(path: "\(name)/\(container)/project.xcproj"), encoding: .utf8)
            #expect(!project.contains("membership-exceptions"), "\(name)")
        }
    }

    /// Whether a program is installed: the generators are on the Mac that makes the fixtures, never on CI.
    static func isInstalled(_ program: String) -> Bool {
        SystemCommandRunner().which(program) != nil
    }

    /// Tuist rewrites only files whose content changes, so a project's file times can't say whether it's stale: the mod
    /// marks it from the edits it sees instead (docs/findings.md, *When a generated project is stale*).
    @Test(.enabled(if: isInstalled("tuist")))
    func tuistLeavesAnUnchangedProjectFileAlone() async throws {
        let root = try Self.copy("forms/tuist")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let file = root.appending(path: "App.xcodeproj/project.pbxproj")
        let past = Date(timeIntervalSince1970: 1_577_836_800)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: file.path)
        let generated = await SystemCommandRunner().run(["/bin/sh", "-c", "cd '\(root.path)' && tuist generate --no-open"], stdin: nil, timeout: .seconds(120))
        #expect(generated.status == 0, "\(generated.stdout)\(generated.stderr)")
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date == past)
    }

    /// A regeneration with another Tuist or XcodeGen shows here, on the Mac that has them; CI has neither and skips.
    @Test(.enabled(if: isInstalled("tuist") && isInstalled("xcodegen")), arguments: ["tuist", "xcodegen"])
    func eachFormWasMadeByTheGeneratorInstalledHere(_ generator: String) async throws {
        let installed = await SystemCommandRunner().run([generator, "version"], stdin: nil, timeout: .seconds(30))
        let version = installed.stdout.split(whereSeparator: \.isNewline).last.map { $0.replacing("Version: ", with: "") } ?? ""
        for name in Self.names where name.hasPrefix(generator) {
            let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.forms.appending(path: "\(name)/fixture.json"))) as? [String: String]
            #expect((fixture?["generatorVersion"] ?? "") == version, "\(name)")
        }
    }
}

/// Where the test bed is checked out: `XCREW_TESTBED`, else a clone beside this repository's.
enum Testbed {
    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let root = ProcessInfo.processInfo.environment["XCREW_TESTBED"].map { URL(fileURLWithPath: $0) }
        ?? repository.deletingLastPathComponent().appending(path: "xcrew-testbed")
    static var isCheckedOut: Bool { FileManager.default.fileExists(atPath: root.appending(path: "forms").path) }
}

/// CI runs the test bed's suite or fails: a missing checkout there is a broken workflow, not a Mac without the clone.
@Suite struct TestbedCheckoutTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == "true"))
    func ciHasTheTestBed() {
        #expect(Testbed.isCheckedOut, "XCREW_TESTBED names no test bed: \(Testbed.root.path)")
    }
}
