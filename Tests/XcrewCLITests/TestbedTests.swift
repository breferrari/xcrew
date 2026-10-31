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

    /// Files a generator writes, and the manifest to edit instead; none for a file no generator writes, the source-file
    /// trap's project included.
    static let generatedFiles: [(file: String, manifest: String?)] = [
        ("forms/tuist/App.xcodeproj/project.pbxproj", "Project.swift"),
        ("forms/tuist/App.xcworkspace/contents.xcworkspacedata", "Project.swift"),
        ("forms/tuist/Derived/InfoPlists/App-Info.plist", "Project.swift"),
        ("forms/tuist/App/ContentView.swift", nil),
        ("forms/tuist-ios/ios/App.xcodeproj/xcshareddata/xcschemes/App.xcscheme", "ios/Project.swift"),
        ("forms/xcodegen/App.xcodeproj/project.pbxproj", "project.yml"),
        ("forms/xcodegen-ios/ios/App.xcodeproj/project.pbxproj", "ios/project.yml"),
        ("forms/xcodegen-ios/ios/App/ContentView.swift", nil),
        ("forms/classic/App.xcodeproj/project.pbxproj", nil),
        ("adversarial/project-swift-trap/App.xcodeproj/project.pbxproj", nil),
    ]

    @Test(arguments: generatedFiles.map(\.file))
    func aFileAGeneratorWritesNamesTheManifestToEdit(_ file: String) async throws {
        let fixture = file.split(separator: "/").prefix(2).joined(separator: "/")
        let root = try Self.copy(fixture)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let edited = root.appending(path: String(file.dropFirst(fixture.count + 1)))
        #expect(FileManager.default.fileExists(atPath: edited.path), "the test bed has no \(file)")
        let context = CheckContext.fake(project: Project(root: root, home: root.appending(path: "home")))
        let answer = try JSONDecoder().decode(ProjectCommand.Answer.self, from: Data(await Run("project", "--generated", edited.path, context: context).text.utf8))
        #expect(answer.manifest == Self.generatedFiles.first { $0.file == file }?.manifest)
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

/// Each form ties files to targets its own way: file references, synchronized folders, the JSON format, and what Tuist
/// and XcodeGen write. A change to the app or its tests selects `AppTests` in all of them.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedAffectedTests {
    static let cases: [(fixture: String, changed: String)] = [
        ("forms/classic", "App/ContentView.swift"), ("forms/classic", "AppTests/GreetingTests.swift"),
        ("forms/classic-ios", "ios/App/ContentView.swift"),
        ("forms/folders", "App/ContentView.swift"), ("forms/folders-ios", "ios/AppTests/GreetingTests.swift"),
        ("forms/json", "App/ContentView.swift"), ("forms/json-ios", "ios/AppTests/GreetingTests.swift"),
        ("forms/tuist", "App/ContentView.swift"), ("forms/tuist-ios", "ios/AppTests/GreetingTests.swift"),
        ("forms/xcodegen", "App/ContentView.swift"), ("forms/xcodegen-ios", "ios/AppTests/GreetingTests.swift"),
    ]

    @Test(arguments: cases.map { "\($0.fixture)/\($0.changed)" })
    func aChangeToTheAppOrItsTestsSelectsAppTests(_ path: String) throws {
        let fixture = path.split(separator: "/").prefix(2).joined(separator: "/")
        let root = try TestbedTests.copy(fixture)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let affected = AffectedTests.of(changed: [String(path.dropFirst(fixture.count + 1))], in: Project(root: root))
        #expect(affected.selections == ["AppTests"], "\(affected.runAll ?? "")")
    }
}

/// A modular Tuist app, one project per module, App on Feature on Core: a module links the one below by its product,
/// across projects. A change selects the tests of its module and of every module above it.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedModularAffectedTests {
    static let cases: [(changed: String, selections: [String])] = [
        ("Modules/Core/Sources/Core.swift", ["AppTests", "CoreTests", "FeatureTests"]),
        ("Modules/Feature/Sources/Feature.swift", ["AppTests", "FeatureTests"]),
        ("Modules/App/Sources/App.swift", ["AppTests"]),
    ]

    @Test(arguments: cases.map(\.changed))
    func aChangeSelectsItsModulesTestsAndEveryModuleAbove(_ changed: String) throws {
        let root = try TestbedTests.copy("modular/tuist-modules")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let affected = AffectedTests.of(changed: [changed], in: Project(root: root))
        #expect(affected.selections == Self.cases.first { $0.changed == changed }?.selections, "\(affected.runAll ?? "")")
    }
}

/// No fixture holds a path of the Mac that made it: Tuist writes its own scheme with the absolute path it ran from.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedPrivacyTests {
    @Test func noFixtureHoldsAnAbsolutePathOfTheMacThatMadeIt() async throws {
        // The files the test bed commits: what a contributor generates or builds there stays out.
        let listed = await SystemCommandRunner().run(["git", "-C", Testbed.root.path, "ls-files", "-z"], stdin: nil, timeout: .seconds(30))
        #expect(listed.succeeded)
        let leaks = listed.stdout.split(separator: "\0").map(String.init).filter { file in
            let text = (try? String(contentsOf: Testbed.root.appending(path: file), encoding: .utf8)) ?? ""
            return Self.holdsAHomePath(text)
        }
        #expect(leaks == [])
    }

    /// Nor does a capture hold the id of the Mac's devices or simulators: the test bed numbers each one it names, from
    /// `00000000-0000-0000-0000-000000000001`.
    @Test func noCaptureHoldsADevicesID() throws {
        let captures = Testbed.root.appending(path: "captures")
        let files = try FileManager.default.subpathsOfDirectory(atPath: captures.path)
        let ids = files.flatMap { file -> [String] in
            guard let text = try? String(contentsOf: captures.appending(path: file), encoding: .utf8) else { return [] }
            return text.matches(of: /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/).map { String($0.output) }
                .filter { !$0.hasPrefix("00000000-0000-0000-0000-") }.map { "\(file): \($0)" }
        }
        #expect(!files.isEmpty)
        #expect(ids == [])
    }

    /// A home folder's path, as written or as JSON escapes it: `\/Users\/`.
    static func holdsAHomePath(_ text: String) -> Bool {
        let plain = text.replacingOccurrences(of: "\\/", with: "/")
        return plain.contains("/Users/") || plain.contains("/home/")
    }

    @Test func aPathJSONEscapedIsStillAPath() {
        #expect(Self.holdsAHomePath(#"["\/Users\/dev\/App\/Pricing.swift"]"#))
        #expect(!Self.holdsAHomePath(#"["\/testbed\/captures\/coverage\/App\/Pricing.swift"]"#))
    }
}

/// The test bed's capture of a real run with `-test-iterations 5`, replayed: the run itself never happens here.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedRepetitionTests {
    @Test func aRealRunsRepetitionsGiveEachTestItsVerdict() throws {
        let listing = try String(contentsOf: Testbed.root.appending(path: "captures/repetitions/tests.json"), encoding: .utf8)
        let found = ResultBundle.repetitions(listing: listing)
        #expect(found.map { "\($0.test) \($0.failed)/\($0.runs) \($0.verdict)" } == ["RepetitionTests/testFailsEveryOtherRun 2/5 flaky", "RepetitionTests/testFailsEveryRun 5/5 real", "RepetitionTests/testPassesEveryRun 0/5 passed"])
    }
}

/// The test bed's capture of what xccov answered about a real run with coverage on, replayed: the test ran
/// `price(for: 2)`, so of `Pricing.swift` every line ran but the discount's `return`, line 5.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedCoverageTests {
    static let bundle = "/coverage/Run.xcresult"

    func captured(_ file: String, in root: URL) throws -> String {
        try String(contentsOf: root.appending(path: file), encoding: .utf8)
            .replacingOccurrences(of: "\\/testbed\\/captures\\/coverage", with: root.path.replacingOccurrences(of: "/", with: "\\/"))
    }

    @Test func aRealRunsLineCountsSayWhichLinesRan() throws {
        let pricing = try String(contentsOf: Testbed.root.appending(path: "captures/coverage/Pricing.json"), encoding: .utf8)
        #expect(ChangedLineCoverage.lines(pricing) == [2: true, 3: true, 4: true, 5: false, 6: true, 7: true, 8: true])
    }

    /// The whole reading, from the captured answers, for a branch that wrote `price(for:)`'s body.
    @Test func aChangedLineTheRealRunDidNotRunIsNamed() async throws {
        let root = try TestbedTests.copy("captures/coverage")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let project = Project(root: root)
        var responses = FakeRunner.branch(at: root, changed: ["App/Pricing.swift"], diffed: ["\(ProjectLayout.canonical(root))/App/Pricing.swift"], diff: "+++ App/Pricing.swift\n@@ -2,0 +3,6 @@\n")
        responses.merge([
            "xcrun xccov view --archive --file-list --json \(Self.bundle)": .init(status: 0, stdout: try captured("file-list.json", in: root)),
            "xcrun xccov view --archive --file \(root.path)/App/Pricing.swift --json \(Self.bundle)": .init(status: 0, stdout: try captured("Pricing.json", in: root)),
        ]) { _, new in new }
        let runner = FakeRunner(responses: responses)
        let output = #"{"schema":"mobilebuildmcp.output.test-result","didError":false,"data":{"summary":{"status":"SUCCEEDED"},"artifacts":{"xcresultPath":"\#(Self.bundle)"}}}"#
        let report = await Report.make(kind: .test, output: ToolOutput(text: output, server: .mobileBuildMCP), home: "/home", runner: runner, project: project)
        #expect(report.notes.contains("xcrew: 5 of 6 changed lines that can run ran in this test run. Not run: Pricing.swift:5."), "\(report.notes)")
    }
}

/// The field fixture's run under `-only-testing:FeatureTests/ProbeTests/testPasses`, replayed from what xccov answered:
/// its report names `FeatureTests.xctest` a test bundle, so a branch that changed `ProbeTests.swift` beside
/// `Greeting.swift` has only `Greeting.swift`'s lines counted, and the test file isn't named.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedFieldCoverageTests {
    static let bundle = "/field/Run.xcresult"

    @Test func aTestBundlesFilesAreLeftOutOfARealRun() async throws {
        let root = try TestbedTests.copy("field")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let captured = { (file: String) in
            try String(contentsOf: Testbed.root.appending(path: "captures/field/\(file)"), encoding: .utf8)
                .replacingOccurrences(of: "\\/testbed\\/field", with: root.path.replacingOccurrences(of: "/", with: "\\/"))
        }
        let greeting = "Modules/Feature/Sources/Greeting.swift"
        var responses = FakeRunner.branch(at: root, changed: [greeting, "Modules/Feature/Tests/ProbeTests.swift"], diffed: ["\(ProjectLayout.canonical(root))/\(greeting)"], diff: "+++ \(greeting)\n@@ -0,0 +1,12 @@\n")
        responses.merge([
            "xcrun xccov view --archive --file-list --json \(Self.bundle)": .init(status: 0, stdout: try captured("coverage.files.json")),
            "xcrun xccov view --archive --file \(root.path)/\(greeting) --json \(Self.bundle)": .init(status: 0, stdout: try captured("coverage.Greeting.json")),
            "xcrun xccov view --report --json \(Self.bundle)": .init(status: 0, stdout: try captured("coverage.report.json")),
        ]) { _, new in new }
        let output = #"{"schema":"mobilebuildmcp.output.test-result","didError":false,"data":{"summary":{"status":"SUCCEEDED","counts":{"passed":1,"failed":0,"skipped":0}},"artifacts":{"xcresultPath":"\#(Self.bundle)"}}}"#
        let report = await Report.make(kind: .test, output: ToolOutput(text: output, server: .mobileBuildMCP), home: "/home", runner: FakeRunner(responses: responses), project: Project(root: root))
        #expect(report.notes.contains("xcrew: 4 of 5 changed lines that can run ran in this test run. Not run: Greeting.swift:12."), "\(report.notes)")
    }
}

/// The test bed's captures of builds that failed because of the Mac, replayed through `xcrew why`: the result
/// MobileBuildMCP gave, and the build log it named. They hold what a real failure says, not how many errors it gave:
/// a corrupt cache doesn't fail the same way twice.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedWhyTests {
    func context() -> CheckContext {
        .fake(.simulators(["iPhone 17"]), project: Project(root: Testbed.root.appending(path: "captures/environment")))
    }

    @Test(arguments: [
        ("module-cache-malformed", "a module in its DerivedData's module cache is corrupt (\"malformed or corrupted precompiled file\"). Remove the cached modules, then build again: rm -rf '/testbed/DerivedData/ModuleCache.noindex' '/testbed/DerivedData/SDKExplicitPrecompiledModules'"),
        ("module-cache-invalid", "is not a valid module file\"). Remove the cached modules, then build again: rm -rf '/testbed/DerivedData/ModuleCache.noindex' '/testbed/DerivedData/SDKExplicitPrecompiledModules'"),
        ("simulator-missing", "no simulator here is named iPhone 1, which the build asked for"),
    ])
    func aRealBuildLogNamesItsCause(capture: String, cause: String) async {
        let run = await Run("why", "--log", Testbed.root.appending(path: "captures/environment/\(capture).log").path, context: context())
        #expect(run.text.hasPrefix("xcrew: this build failed because of the Mac, not the code: "), "\(run.text)")
        #expect(run.text.contains(cause), "\(run.text)")
    }

    /// MobileBuildMCP's own result names the same cause. The log it points at isn't on this Mac, so the DerivedData
    /// goes unnamed where the result doesn't name it.
    @Test(arguments: [
        ("module-cache-malformed", "\"malformed or corrupted precompiled file\"). Remove ModuleCache.noindex and SDKExplicitPrecompiledModules from the DerivedData this build used"),
        ("module-cache-invalid", "rm -rf '/testbed/DerivedData/ModuleCache.noindex'"),
        ("simulator-missing", "no simulator here is named iPhone 1"),
    ])
    func aRealResultNamesItsCause(capture: String, cause: String) async throws {
        let result = try String(contentsOf: Testbed.root.appending(path: "captures/environment/\(capture).txt"), encoding: .utf8)
        let run = await Run("why", "--server", "MobileBuildMCP", context: context(), stdin: result)
        #expect(run.text.contains(cause), "\(run.text)")
    }
}

/// The test bed's captures of three failing snapshot tests (swift-snapshot-testing under XCTest and Swift Testing,
/// iOSSnapshotTestCase), replayed: the attachments xcresulttool exported from a run through `xcodebuild test` and one
/// through MobileBuildMCP's `test_sim`, and the text `test_sim` gave.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedSnapshotTests {
    static let captures = Testbed.root.appending(path: "captures/snapshots")

    /// A bundle whose every export is a fresh copy of one capture's, kept under a cache of its own.
    static func bundle(_ capture: String) -> (bundle: ResultBundle, cache: URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "xcrew-tests-\(UUID().uuidString)")
        let export: @Sendable () -> URL = {
            let folder = root.appending(path: "export-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: captures.appending(path: capture), to: folder)
            return folder
        }
        return (ResultBundle(path: "/snapshots/Snapshots.xcresult", runner: FakeRunner(), exportFolder: export), root)
    }

    @Test(arguments: [
        ("PointFreeXCTests", "testSquare", ["reference_0_00000000-0000-0000-0000-000000000016.png", "failure_1_00000000-0000-0000-0000-000000000016.png", "difference_2_00000000-0000-0000-0000-000000000016.png"]),
        ("PointFreeSwiftTests", "square", ["reference_0_00000000-0000-0000-0000-000000000006.png", "failure_0_00000000-0000-0000-0000-000000000008.png", "difference_0_00000000-0000-0000-0000-000000000018.png"]),
        ("UberTests", "testSquare", ["Reference Image_0_00000000-0000-0000-0000-000000000007.png", "Failed Image_1_00000000-0000-0000-0000-000000000007.png", "Diffed Image_2_00000000-0000-0000-0000-000000000007.png"]),
    ])
    func eachLibrarysImagesComeReferenceFailureDifference(suite: String, name: String, expected: [String]) async throws {
        let (bundle, root) = Self.bundle("xcodebuild")
        defer { try? FileManager.default.removeItem(at: root) }
        let test = TestID(suite: suite, name: name)
        let images = try #require(await bundle.attachments(of: test, onlyFailures: false) { FailureImages.keep(of: test, from: $0, in: root.appending(path: "images")) })
        #expect(images.paths.map { URL(fileURLWithPath: $0).lastPathComponent } == expected)
        // Each is a PNG, though pointfree's XCTest images export with no extension.
        for path in images.paths { #expect(FileManager.default.contents(atPath: path)?.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47])) }
    }

    /// What Claude reads after a `test_sim` run: each failed test's three images under it, once, though the text lists a
    /// test twice.
    @Test func aRealTestSimResultListsEachTestsImagesUnderIt() async throws {
        let (bundle, root) = Self.bundle("mobilebuildmcp")
        defer { try? FileManager.default.removeItem(at: root) }
        let text = try String(contentsOf: Self.captures.appending(path: "test_sim.txt"), encoding: .utf8)
        let added = try #require(await FailureNotes.adding(to: MobileText(text), from: bundle, keepingImagesIn: root.appending(path: "images"))).text.text
        let listed = added.components(separatedBy: "\n").filter { $0.hasPrefix("      image: ") }.map { URL(fileURLWithPath: String($0.dropFirst("      image: ".count))).lastPathComponent }
        #expect(listed == [
            "reference_0_00000000-0000-0000-0000-000000000016.png", "failure_0_00000000-0000-0000-0000-000000000008.png", "difference_0_00000000-0000-0000-0000-000000000014.png",
            "reference_0_00000000-0000-0000-0000-000000000003.png", "failure_1_00000000-0000-0000-0000-000000000003.png", "difference_2_00000000-0000-0000-0000-000000000003.png",
            "Reference Image_0_00000000-0000-0000-0000-000000000015.png", "Failed Image_1_00000000-0000-0000-0000-000000000015.png", "Diffed Image_2_00000000-0000-0000-0000-000000000015.png",
        ], "\(added)")
    }
}

/// Why every failed test's attachments are exported, rather than only those of a test whose details say it has media:
/// `hasMediaAttachments` is false for tests that attached screen recordings and screenshots.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedMediaFlagTests {
    @Test(arguments: ["xcodebuild", "mobilebuildmcp"])
    func theDetailsSayNoMediaForUITestsThatAttachedImages(_ capture: String) throws {
        let folder = Testbed.root.appending(path: "captures/uitests/\(capture)")
        let manifest = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appending(path: "manifest.json"))) as? [[String: Any]])
        for test in manifest {
            let identifier = try #require(test["testIdentifier"] as? String)
            let name = TestID(xcresultID: identifier).name
            let names = (test["attachments"] as? [[String: Any]] ?? []).compactMap { $0["suggestedHumanReadableName"] as? String }
            #expect(names.contains { $0.hasPrefix("Screen Recording") || $0.hasPrefix("UI Snapshot") }, "\(identifier)")
            let details = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appending(path: "details-\(name).json"))) as? [String: Any])
            #expect(details["hasMediaAttachments"] as? Bool == false, "\(identifier)")
        }
    }
}

/// The evidence pack's changed lines, from the newest test run's coverage and the newest build's warnings in this
/// project's MobileBuildMCP workspace, each dated by its run: the coverage capture's real answers.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedEvidenceTests {
    /// A copy of the coverage capture on a branch that wrote `price(for:)`'s body, its last commit at `committed`, with
    /// MobileBuildMCP's newest test run and build at `ran`.
    static func project(committed: Date, ran: Date) throws -> (project: Project, context: CheckContext) {
        let root = try TestbedTests.copy("captures/coverage")
        let project = Project(root: root)
        let workspace = root.appending(path: "home/Library/Developer/MobileBuildMCP/workspaces/\(RunLog.workspaceKey(root: root.path))")
        let bundle = workspace.appending(path: "result-bundles/test_sim_1.xcresult"), log = workspace.appending(path: "logs/build_sim_1.log")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "\(root.path)/App/Pricing.swift:4:13: warning: initialization of immutable value 'rate' was never used\n\(root.path)/App/Other.swift:2:5: warning: deprecated\n".write(to: log, atomically: true, encoding: .utf8)
        for item in [bundle, log] { try FileManager.default.setAttributes([.modificationDate: ran], ofItemAtPath: item.path) }
        var responses = FakeRunner.branch(at: root, changed: ["App/Pricing.swift"], diffed: ["\(ProjectLayout.canonical(root))/App/Pricing.swift"], diff: "+++ App/Pricing.swift\n@@ -2,0 +3,6 @@\n")
        let captured = { (file: String) in
            try String(contentsOf: root.appending(path: file), encoding: .utf8).replacingOccurrences(of: "\\/testbed\\/captures\\/coverage", with: root.path.replacingOccurrences(of: "/", with: "\\/"))
        }
        responses.merge([
            "git -C \(root.path) log -1 --format=%ct": .init(status: 0, stdout: "\(Int(committed.timeIntervalSince1970))\n"),
            "xcrun xccov view --archive --file-list --json \(bundle.path)": .init(status: 0, stdout: try captured("file-list.json")),
            "xcrun xccov view --archive --file \(root.path)/App/Pricing.swift --json \(bundle.path)": .init(status: 0, stdout: try captured("Pricing.json")),
        ]) { _, new in new }
        return (project, CheckContext.fake(FakeRunner(responses: responses), project: project))
    }

    static let ran = Date(timeIntervalSince1970: 1_793_370_240)
    static let input = #"{"ledger":[],"times":[]}"#

    @Test func theChangedLinesComeFromTheNewestRunsDatedByThem() async throws {
        let (project, context) = try Self.project(committed: Self.ran.addingTimeInterval(-3600), ran: Self.ran)
        defer { try? FileManager.default.removeItem(at: project.root.deletingLastPathComponent()) }
        let run = await Run("evidence", context: context, stdin: Self.input)
        #expect(run.text == """
            ## Evidence

            Changed lines:
            - From the test run of 2026-10-30 14:24 UTC: 5 of 6 changed lines that can run ran in this test run. Not run: Pricing.swift:5.
            - From the build of 2026-10-30 14:24 UTC: 1 of 2 warnings are in lines this branch changed: Pricing.swift:4 initialization of immutable value 'rate' was never used.
            """, "\(run.text)")
    }

    /// A run before the branch's last commit is named as older, never left out and never shown as current.
    @Test func runsOlderThanTheLastCommitAreNamedOlder() async throws {
        let (project, context) = try Self.project(committed: Self.ran.addingTimeInterval(36 * 60), ran: Self.ran)
        defer { try? FileManager.default.removeItem(at: project.root.deletingLastPathComponent()) }
        let run = await Run("evidence", context: context, stdin: Self.input)
        #expect(run.text.contains("- From the test run of 2026-10-30 14:24 UTC, older than the branch's last commit (2026-10-30 15:00 UTC): 5 of 6"), "\(run.text)")
        #expect(run.text.contains("- From the build of 2026-10-30 14:24 UTC, older than the branch's last commit (2026-10-30 15:00 UTC): 1 of 2 warnings"), "\(run.text)")
    }
}

/// The test bed's field captures: a module's probe tests run five times with relaunch, and a crashing test, through
/// MobileBuildMCP's `test_sim` over MCP, with what xcresulttool answered about each result bundle. Each text opens with a
/// blank line, as MobileBuildMCP's MCP results do.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedFieldTests {
    static let field = Testbed.root.appending(path: "captures/field")
    static let home = "/testbed/home"

    static func captured(_ file: String) throws -> String {
        try String(contentsOf: field.appending(path: file), encoding: .utf8)
    }

    /// The bundle a capture's text names, as the report expands it.
    static func bundle(in text: String) throws -> String {
        let named = try #require(text.firstMatch(of: /result-bundles\/(\S+\.xcresult)/)?.1)
        let workspace = try #require(text.firstMatch(of: /workspaces\/([^\/\s]+)\//)?.1)
        return "\(home)/Library/Developer/MobileBuildMCP/workspaces/\(workspace)/result-bundles/\(named)"
    }

    /// What xcresulttool answered about a capture's bundle, as a runner answering the report's calls.
    static func runner(_ capture: String, bundle: String) throws -> FakeRunner {
        let x = "xcrun xcresulttool get test-results"
        var responses: [String: CommandResult] = [
            "\(x) tests --path \(bundle) --compact": .init(status: 0, stdout: try captured("\(capture).tests.json")),
            "\(x) summary --path \(bundle) --compact": .init(status: 0, stdout: try captured("\(capture).summary.json")),
        ]
        for file in try FileManager.default.contentsOfDirectory(atPath: field.path) where file.hasPrefix("\(capture).details.") {
            let test = file.dropFirst("\(capture).details.".count).dropLast(".json".count).replacingOccurrences(of: ".", with: "/")
            responses["\(x) test-details --test-id \(test)() --path \(bundle) --compact"] = .init(status: 0, stdout: try captured(file))
        }
        return FakeRunner(responses: responses)
    }

    @Test func aRepeatedRunListsEachTestOnceWithItsRunsAndTheSkipReason() async throws {
        let text = try Self.captured("probes.txt")
        let bundle = try Self.bundle(in: text)
        let report = await Report.make(kind: .test, output: ToolOutput(text: text, server: .mobileBuildMCP, isError: true), home: Self.home, runner: try Self.runner("probes", bundle: bundle), repeated: true)
        let result = try #require(report.result, "the report left the server's text as it was")
        #expect(result.components(separatedBy: "✗ ProbeTests / testFlaky").count == 2, "\(result)")
        #expect(result.contains("    /testbed/field/Modules/Feature/Tests/ProbeTests.swift:19\n      failed 3 of 5 runs"), "\(result)")
        #expect(result.contains("    /testbed/field/Modules/Feature/Tests/ProbeTests.swift:11\n      failed 5 of 5 runs"), "\(result)")
        #expect(result.contains("  ⏭️ ProbeTests/testSkipped() (0.018s)\n      skipped: waits for the farewell screen"), "\(result)")
    }

    /// A crash's error text is the one the run printed under Errors; the crash log names the test's own frame, its file
    /// and line, below the runtime's frames.
    @Test func aCrashGetsItsErrorTextTheTestsLineAndItsFrames() async throws {
        let text = try Self.captured("crash.txt")
        let bundle = try Self.bundle(in: text)
        let export = FileManager.default.temporaryDirectory.appending(path: "xcrew-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
        try Self.captured("crash.ips").write(to: export.appending(path: "crash.ips"), atomically: true, encoding: .utf8)
        let runner = try Self.runner("crash", bundle: bundle)
        let added = try #require(await FailureNotes.adding(to: MobileText(text), from: ResultBundle(path: bundle, runner: runner, exportFolder: { export })))
        let lines = added.text.text.components(separatedBy: "\n")
        let crash = try #require(lines.firstIndex { $0.contains("✗ CrashTests / testOutOfRange(): Crash:") })
        #expect(Array(lines[(crash + 1)...].prefix(3)) == [
            "    ProbeTests.swift:35",
            "      crashed: EXC_BREAKPOINT (SIGTRAP)",
            "      Fatal error: Index out of range",
        ], "\(added.text.text)")
        #expect(lines.contains("      FeatureTests  CrashTests.testOutOfRange()"), "\(added.text.text)")
    }
}

/// The field fixture, one scheme per module, with a workspace scheme that tests every module: `affected` names the
/// schemes that test only targets the change can break, so a test builds one module rather than every one.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedAffectedSchemeTests {
    static func answer(changed: [String]) async throws -> [String: Any] {
        let root = try TestbedTests.copy("field")
        let project = Project(root: root)
        project.writeScheme("UnitTests", testing: ["CoreTests", "DataTests", "FeatureTests", "AppTests"], container: "Field.xcworkspace", folder: "Field.xcworkspace/xcshareddata")
        let runner = FakeRunner(responses: FakeRunner.branch(at: root, changed: changed, diffed: [], diff: ""))
        let text = await Run("affected", context: .fake(runner, project: project)).text
        return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], "\(text)")
    }

    @Test func aChangeInOneModuleNamesTheSchemesThatTestOnlyWhatItCanBreak() async throws {
        let answer = try await Self.answer(changed: ["Modules/Feature/Sources/Feature.swift"])
        let schemes = try #require(answer["schemes"] as? [[String: Any]], "\(answer)")
        #expect(schemes.map { $0["name"] as? String } == ["Feature", "App"])
        #expect(schemes.map { $0["container"] as? String } == ["Modules/Feature/Feature.xcodeproj", "Modules/App/App.xcodeproj"])
        #expect(schemes.map { $0["targets"] as? [String] } == [["FeatureTests"], ["AppTests", "AppUITests"]])
    }

    /// A change the reading can't place can break anything: no selection, so no scheme.
    @Test func aChangeThatRunsEverythingNamesNoScheme() async throws {
        let answer = try await Self.answer(changed: ["Modules/Feature/Project.swift"])
        #expect(answer["schemes"] == nil, "\(answer)")
    }
}

/// Captures K and N, as MobileBuildMCP answered them: `xcrew note` gives each its way around.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedToolErrorNoteTests {
    @Test(arguments: [("two-display", "`xcrun simctl io <udid> screenshot --display=<id> <file>`"), ("lldb-expr", "`xcrew setup --debugger-backend lldb-cli`")])
    func aCapturedErrorGetsItsNote(_ capture: String, names: String) async throws {
        let text = try String(contentsOf: Testbed.root.appending(path: "captures/field/\(capture).txt"), encoding: .utf8)
        let answer = await Run("note", "--server", "MobileBuildMCP", "--error", stdin: text).text
        #expect(answer.contains(names), "\(answer)")
    }
}

/// The field fixture's four layers, App on Feature on Data on Core, are its module graph: each module imports the one
/// below and nothing else of the workspace's, so every import is declared and no dependency goes unimported.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedModuleGraphTests {
    @Test func theFieldFixturesLayersAreItsModules() throws {
        let root = try TestbedTests.copy("field")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let graph = ModuleGraph.read(Project(root: root))
        #expect(graph.unread == nil)
        #expect(graph.modules.map { [$0.name] + $0.dependencies } == [["App", "Feature"], ["Core"], ["Data", "Core"], ["Feature", "Data"]])
        #expect(graph.modules.map(\.project) == ["Modules/App/App.xcodeproj", "Modules/Core/Core.xcodeproj", "Modules/Data/Data.xcodeproj", "Modules/Feature/Feature.xcodeproj"])
        #expect(graph.imports.filter { $0.placement != .declared } == [])
        #expect(Set(graph.imports.filter { !$0.target.hasSuffix("Tests") }.map { "\($0.target) \($0.module)" }) == ["App Feature", "Data Core", "Feature Data"])
        #expect(graph.unimported == [])
        #expect(graph.notes == [])
    }

    /// An import past the layer below, and one up the layers, written at the top of a copy's sources: Tuist lists each
    /// file in the project, so a new file would belong to no target until the project is generated again.
    @Test func importsAcrossTheLayersArePlaced() throws {
        let root = try TestbedTests.copy("field")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        for (file, line) in [("Modules/App/Sources/App.swift", "import Core\n"), ("Modules/Core/Sources/Core.swift", "import Feature\n")] {
            let url = root.appending(path: file)
            try (line + String(contentsOf: url, encoding: .utf8)).write(to: url, atomically: true, encoding: .utf8)
        }
        let crossing = ModuleGraph.read(Project(root: root)).imports.filter { $0.placement != .declared }
        #expect(crossing == [
            .init(target: "App", file: "Modules/App/Sources/App.swift", line: 1, module: "Core", placement: .transitiveOnly),
            .init(target: "Core", file: "Modules/Core/Sources/Core.swift", line: 1, module: "Feature", placement: .upward),
        ])
    }

    @Test(arguments: [("Modules/Core/Sources/Core.swift", "Core"), ("Modules/Data/Sources/Data.swift", "Data"), ("Modules/Feature/Sources/Greeting.swift", "Feature"), ("Modules/App/Sources/FieldApp.swift", "App"), ("Modules/Feature/Tests/ProbeTests.swift", "FeatureTests")])
    func eachFileIsOwnedByItsModule(_ file: String, _ owner: String) throws {
        let root = try TestbedTests.copy("field")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        #expect(FileOwners.of(file, in: Project(root: root)).targets == [owner])
    }
}

/// The setup form's choices on the field fixture: one shared scheme per module, the App's building the app and running
/// its unit and UI tests, each other module's running its own unit tests.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedSetupChoicesTests {
    @Test func theFieldFixturesSchemesSayWhatTheyDo() throws {
        let root = try TestbedTests.copy("field")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let choices = SetupChoices.read(container: "Field.xcworkspace", containers: ["Field.xcworkspace"], containerProblem: nil, in: Project(root: root), catalog: SimulatorCatalog(devices: []))
        #expect(choices.schemes.map { "\($0.name) \($0.container) \($0.roles.map(\.rawValue).joined(separator: ","))" }.sorted() == [
            "App Modules/App/App.xcodeproj app,unit-tests,ui-tests",
            "Core Modules/Core/Core.xcodeproj unit-tests",
            "Data Modules/Data/Data.xcodeproj unit-tests",
            "Feature Modules/Feature/Feature.xcodeproj unit-tests",
        ])
        #expect(choices.picks == SetupChoices.Picks(appScheme: "App", uiScheme: "App", testScheme: "App", bundleID: "dev.xcrew.testbed.App"))
    }
}

/// The concurrency fixture's real diagnostics: xcodebuild's log of its frameworks, MobileBuildMCP's log of the same
/// build, and the Swift 6 app's failed build. Each log's paths are the capture's, rewritten to a copy of the fixture so
/// its project names each file's module.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedConcurrencyTests {
    static func report(_ capture: String) async throws -> ConcurrencyReport {
        let root = try TestbedTests.copy("concurrency")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let log = try String(contentsOf: Testbed.root.appending(path: "captures/concurrency/\(capture)"), encoding: .utf8)
        let copy = root.appending(path: "build.log")
        try log.replacing("/testbed/concurrency", with: ProjectLayout.canonical(root)).write(to: copy, atomically: true, encoding: .utf8)
        return try await ConcurrencyReport.read(log: copy, project: Project(root: root), groups: { _ in .read(docs: nil) }, using: FakeRunner())
    }

    @Test(arguments: ["xcodebuild-warnings.log", "build_sim.log"])
    func theFrameworksDiagnosticsByGroupAndModule(_ capture: String) async throws {
        let report = try await Self.report(capture)
        #expect(report.groups.map { "\($0.name) \($0.count)" } == ["MutableGlobalVariable 2", "SendingClosureRisksDataRace 2", "SendingRisksDataRace 1"])
        #expect(report.modules.map { "\($0.name) \($0.count)" } == ["Kit 3", "Feature 2"])
        #expect(report.ungrouped == 1)
        #expect(report.errors == 0)
    }

    @Test func theSwift6AppsErrorIsCounted() async throws {
        let report = try await Self.report("xcodebuild-errors.log")
        #expect(report.count == 1)
        #expect(report.errors == 1)
        #expect(report.modules.map(\.name) == ["App"])
    }

    /// xcodebuild's log writes each warning two or four times; counted once each, they're MobileBuildMCP's own list.
    @Test func eachDiagnosticOnceIsMobileBuildMCPsList() throws {
        let log = try String(contentsOf: Testbed.root.appending(path: "captures/concurrency/xcodebuild-warnings.log"), encoding: .utf8)
        let distinct = Set(log.split(separator: "\n").compactMap(CompilerDiagnostic.parse))
        let listed = try String(contentsOf: Testbed.root.appending(path: "captures/concurrency/build_sim.txt"), encoding: .utf8)
            .split(separator: "\n").filter { $0.hasPrefix("  ⚠ ") }
        #expect(distinct.count == listed.count)
        #expect(Set(distinct.map(\.message)) == Set(listed.map { line in String(line.dropFirst(4)).replacing(/\ \[#[\w:]+\]$/, with: "") }))
    }
}

/// The name rule stands in where an Xcode ships no group docs: every group this Mac's Xcode documents as concurrency's,
/// it must catch too, so it's never weaker than the docs, and a new Swift's group shows here first.
@Suite(.enabled(if: InstalledGroupDocs.folder != nil, "no Xcode with Swift's diagnostic group docs"))
struct InstalledGroupDocsTests {
    @Test func theNameRuleCatchesEveryGroupTheDocsSayIsConcurrencys() {
        let docs = ConcurrencyGroups.read(docs: InstalledGroupDocs.folder)
        #expect(docs.isFromDocs)
        // Xcode 26.0 documents two groups, neither about concurrency; where the docs cover many, some must be.
        if docs.documented.count >= 20 {
            #expect(docs.titles.count >= 5, "too few concurrency groups in the docs at \(InstalledGroupDocs.folder?.path ?? ""): their shape changed; read: \(docs.documented.sorted())")
        }
        for group in docs.titles.keys.sorted() {
            #expect(ConcurrencyGroups.namesConcurrency(group), "\(group): its doc says concurrency, its name doesn't")
        }
    }
}

/// The group docs of the Xcode builds use, as the command finds it: `DEVELOPER_DIR`, else `xcode-select`'s, when it
/// ships them.
enum InstalledGroupDocs {
    static let folder: URL? = {
        var developer = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
        if developer == nil {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
            process.arguments = ["-p"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardInput = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            process.waitUntilExit()
            developer = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let developer, let app = Xcodes.app(holding: developer) else { return nil }
        let folder = ConcurrencyGroups.docs(in: app)
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
    }()
}

/// The test bed's raw captures: MobileBuildMCP's `test_sim` answers whole, with the log each names. A serial XCTest run
/// writes `Test Case '-[…]' passed|failed|skipped (…)`, not the parallel runner's `Test case '…'`.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedRawTests {
    static let raw = Testbed.root.appending(path: "captures/raw")

    static func captured(_ file: String) throws -> String {
        try String(contentsOf: raw.appending(path: file), encoding: .utf8)
    }

    /// The text MobileBuildMCP's answer hands Claude Code, its `content`, which the mod reads.
    static func content(_ capture: String) throws -> String {
        let answer = try #require(try JSONSerialization.jsonObject(with: Data(captured("\(capture).json").utf8)) as? [String: Any])
        let result = (answer["result"] as? [String: Any]) ?? answer
        let content = try #require(result["content"] as? [[String: Any]])
        return content.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    /// Five tests ran, one an expected failure, which MobileBuildMCP's counts leave out: 1 passed, 2 failed, 1 skipped.
    @Test func aSerialRunsFinishedTestsAreCountedButItsExpectedFailure() throws {
        #expect(RunLog.testsFinished(in: Substring(try Self.captured("serial.log"))) == 4)
    }

    /// The count a run reaches is the total the next run's line measures against: both count the same tests.
    @Test func aSerialRunsCountIsTheTotalMobileBuildMCPGivesIt() throws {
        let total = try #require(ToolOutput(text: try Self.content("serial"), server: .mobileBuildMCP).testTotal)
        #expect(RunLog.testsFinished(in: Substring(try Self.captured("serial.log"))) == total)
    }
}
