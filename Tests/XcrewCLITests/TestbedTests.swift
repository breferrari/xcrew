import Foundation
import Testing
@testable import XcrewCLI
@testable import XcrewCore
import XcrewTestSupport

/// The test bed's forms: one app as each project form, at the root and under `ios/` (`scripts/testbed/generate.sh`).
/// Each is checked against its own `expect.xcrew.json` on a copy, as a repository of its own, with no build.
@Suite struct TestbedTests {
    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let forms = repository.appending(path: "Tests/Testbed/forms")

    static var names: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: forms.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

    /// What `expect.xcrew.json` states, and what the checks below find.
    struct Outcome: Codable, Equatable {
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

    /// A copy of the fixture with a `.git` of its own, so its root is a repository's.
    static func copy(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "xcrew-testbed-\(UUID().uuidString)/\(name)")
        try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: forms.appending(path: name), to: root)
        try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
        return root
    }

    static func outcome(of name: String, expecting expected: Outcome) async throws -> Outcome {
        let root = try copy(name)
        let project = Project(root: root, home: root.deletingLastPathComponent().appending(path: "home"))
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
            containerProblem: answer.containerProblem.flatMap { problem in expected.containerProblem.map { problem.contains($0) ? $0 : problem } },
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

    static func expected(_ name: String) throws -> Outcome {
        try JSONDecoder().decode(Outcome.self, from: Data(contentsOf: forms.appending(path: "\(name)/expect.xcrew.json")))
    }

    @Test func everyFormIsHere() {
        #expect(Self.names == ["classic", "classic-ios", "folders", "folders-ios", "json", "json-ios", "tuist", "tuist-ios", "tuist-ungenerated", "tuist-ungenerated-ios", "xcodegen", "xcodegen-ios"])
    }

    @Test(arguments: names)
    func eachFormIsWhatItsExpectationSays(_ name: String) async throws {
        let expected = try Self.expected(name)
        let actual = try await Self.outcome(of: name, expecting: expected)
        #expect(actual == expected, "found \(actual)")
    }

    /// The forms hold one app, so they differ only where a form must: its generator, and where the project sits.
    @Test func theFormsDifferOnlyInTheirGeneratorAndPlace() throws {
        let built = try Self.names.filter { !$0.hasPrefix("tuist-ungenerated") }.map { name in
            var outcome = try Self.expected(name)
            (outcome.generator, outcome.generatorRoot, outcome.isGenerated) = (nil, nil, false)
            outcome.container = outcome.container.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
            return outcome
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let distinct = Set(try built.map { String(decoding: try encoder.encode($0), as: UTF8.self) })
        #expect(distinct.count == 1, "\(distinct.sorted())")
    }

    /// Every file of a JSON form's folders is in its target: `xcodeproj` records them all as exclusions when phases come
    /// after the folder (docs/findings.md, *Making the test bed's projects*).
    @Test func theJSONFormsExcludeNothing() throws {
        for name in Self.names where name.hasPrefix("json") {
            let folder = name.hasSuffix("-ios") ? "\(name)/ios" : name
            let project = try String(contentsOf: Self.forms.appending(path: "\(folder)/App.xcodeproj/project.xcproj"), encoding: .utf8)
            #expect(!project.contains("membership-exceptions"), "\(name)")
        }
    }

    /// Whether a program is on this Mac's PATH: the generators are on the one that makes the fixtures, never on CI.
    static func isInstalled(_ program: String) -> Bool {
        (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").contains { FileManager.default.isExecutableFile(atPath: "\($0)/\(program)") }
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
