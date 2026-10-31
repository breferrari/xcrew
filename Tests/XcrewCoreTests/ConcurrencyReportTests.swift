import Foundation
import Synchronization
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// A build's concurrency diagnostics by the compiler's own groups: which groups count comes from the toolchain's docs,
/// each diagnostic counts once, and one with no group is counted apart.
@Suite struct ConcurrencyReportTests {
    @Test func aLineGivesItsPlaceKindMessageAndGroups() {
        let warning = CompilerDiagnostic.parse("/p/My Kit/Kit.swift:24:17: warning: sending 'box' risks causing data races; this is an error in the Swift 6 language mode [#RegionIsolation::SendingRisksDataRace]")
        #expect(warning == CompilerDiagnostic(path: "/p/My Kit/Kit.swift", line: 24, isError: false, message: "sending 'box' risks causing data races; this is an error in the Swift 6 language mode", groups: ["RegionIsolation", "SendingRisksDataRace"]))
        #expect(CompilerDiagnostic.parse("/p/App.swift:12:5: error: var 'appCount' is not concurrency-safe [#MutableGlobalVariable]")?.groups == ["MutableGlobalVariable"])
        #expect(CompilerDiagnostic.parse("/p/App.swift:12:5: error: var 'appCount' is not concurrency-safe [#MutableGlobalVariable]")?.isError == true)
        #expect(CompilerDiagnostic.parse("/p/K.swift:9: warning: stored property 'box' has non-Sendable type 'Box'")?.groups == [])
        #expect(CompilerDiagnostic.parse("note: Building targets in dependency order") == nil)
        #expect(CompilerDiagnostic.parse("xcodebuild: error: Unable to find a destination") == nil)
        // The earliest mark is the diagnostic's, whatever its message says.
        #expect(CompilerDiagnostic.parse("/p/A.swift:3:1: error: foo: warning: bar [#ActorIsolatedCall]") == CompilerDiagnostic(path: "/p/A.swift", line: 3, isError: true, message: "foo: warning: bar", groups: ["ActorIsolatedCall"]))
    }

    /// A docs folder as a toolchain ships it: one file per group, headed `# <title> (<Group>)`.
    func docs(_ files: [String: String]) -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "xcrew-docs-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, text) in files { try? text.write(to: folder.appending(path: "\(name).md"), atomically: true, encoding: .utf8) }
        return folder
    }

    @Test func theToolchainsDocsSayWhichGroupsAreConcurrencys() {
        let groups = ConcurrencyGroups.read(docs: docs([
            "mutable-global-variable": "# Unsafe mutable global and static variables (MutableGlobalVariable)\n\n## Overview\n\nMutable global and static variables can cause data races in your program.\n",
            "sendable-closure-captures": "# Captures in a `@Sendable` closure (SendableClosureCaptures)\n\n`@Sendable` closures can be called multiple times concurrently.\n",
            "deprecated-declaration": "# Deprecated declaration warnings (DeprecatedDeclaration)\n\nWarnings related to deprecated APIs.\n",
            "diagnostic-groups": "# Diagnostic groups\n\nDetailed explanations, concurrency among them.\n",
            // A title naming `Sendable` counts; a `Sendable` in an example's code doesn't.
            "explicit-sendable-annotations": "# Explicit `Sendable` annotations on public type declarations (ExplicitSendable)\n\nAdds a warning for any public types without a `Sendable` annotation.\n",
            "implicit-strong-capture": "# Implicit strong captures of weak capture list items (ImplicitStrongCapture)\n\n```swift\nfinal class DataService: Sendable {}\n```\n",
        ]))
        #expect(groups.isFromDocs)
        #expect(groups.titles == ["MutableGlobalVariable": "Unsafe mutable global and static variables", "SendableClosureCaptures": "Captures in a `@Sendable` closure", "ExplicitSendable": "Explicit `Sendable` annotations on public type declarations"])
        #expect(!groups.counts(["ImplicitStrongCapture"]))
        #expect(groups.counts(["MutableGlobalVariable"]))
        #expect(!groups.counts(["DeprecatedDeclaration"]))
        // A group under a concurrency group counts, its own doc or not.
        #expect(ConcurrencyGroups(titles: ["RegionIsolation": "Region isolation"], isFromDocs: true).counts(["RegionIsolation", "SendingRisksDataRace"]))
    }

    /// Swift 6.2's docs, which Xcode 26 ships, head a doc with its title alone: the file's name gives the group.
    @Test func aDocHeadedWithItsTitleAloneIsNamedByItsFile() {
        let groups = ConcurrencyGroups.read(docs: docs([
            "sendable-closure-captures": "# Captures in a `@Sendable` closure\n\n`@Sendable` closures can be called multiple times concurrently.\n",
        ]))
        #expect(groups.titles == ["SendableClosureCaptures": "Captures in a `@Sendable` closure"])
    }

    /// A doc may say less than its group's name: Swift 6.2's `IsolatedConformances` speaks of neither concurrency nor
    /// data races. The docs add groups and titles; they never take one away.
    @Test func aGroupsNameCountsWhereItsDocIsSilent() {
        let groups = ConcurrencyGroups.read(docs: docs([
            "isolated-conformances": "# Global-actor isolated conformances\n\nA protocol conformance can be isolated to a specific global actor.\n",
        ]))
        #expect(groups.counts(["IsolatedConformances"]))
    }

    @Test func withoutDocsTheGroupsNameDecides() {
        let groups = ConcurrencyGroups.read(docs: nil)
        #expect(!groups.isFromDocs)
        for name in ["SendableClosureCaptures", "SendingRisksDataRace", "ActorIsolatedCall", "MutableGlobalVariable", "NonisolatedNonsendingByDefault", "PreconcurrencyImport"] {
            #expect(groups.counts([name]), "\(name)")
        }
        for name in ["DeprecatedDeclaration", "NoUsage", "ExistentialAny"] { #expect(!groups.counts([name]), "\(name)") }
    }

    /// A log as xcodebuild writes one: each warning more than once, one outside concurrency, one with no group, an error.
    static let log = """
        /p/Kit/Kit.swift:1:12: warning: var 'sharedCount' is not concurrency-safe [#MutableGlobalVariable]
        /p/Kit/Kit.swift:24:17: warning: sending 'box' risks causing data races [#RegionIsolation::SendingRisksDataRace]
        /p/Kit/Kit.swift:1:12: warning: var 'sharedCount' is not concurrency-safe [#MutableGlobalVariable]
        /p/Kit/Kit.swift:34:9: warning: initialization of immutable value 'unused' was never used [#NoUsage]
        /p/Kit/Kit.swift:9:16: warning: stored property 'box' of 'Sendable'-conforming struct 'Holder' has non-Sendable type 'Box'
        /p/Feature/Feature.swift:3:12: warning: var 'featureFlags' is not concurrency-safe [#MutableGlobalVariable]
        /p/Feature/Feature.swift:3:12: warning: var 'featureFlags' is not concurrency-safe [#MutableGlobalVariable]
        /p/App/App.swift:12:5: error: var 'appCount' is not concurrency-safe [#MutableGlobalVariable]
        /elsewhere/Package.swift:2:1: warning: sending 'x' risks causing data races [#RegionIsolation::SendingRisksDataRace]

        """

    /// Kit, Feature and App, each a folder of its own in one project, in the JSON format.
    func project() -> Project {
        let project = Project.temporary(containing: ["Concurrency.xcodeproj"])
        project.write("""
            {
              "files": [
                { "kind": "folder", "path": "Kit", "target-membership": [ "Kit" ] },
                { "kind": "folder", "path": "Feature", "target-membership": [ "Feature" ] },
                { "kind": "folder", "path": "App", "target-membership": [ "App" ] },
              ],
              "targets": [
                { "name": "Kit", "id": "K", "product-type": "framework" },
                { "name": "Feature", "id": "F", "product-type": "framework", "dependencies": [ "Kit" ] },
                { "name": "App", "id": "A", "product-type": "application", "dependencies": [ "Feature" ] },
              ],
            }
            """, to: "Concurrency.xcodeproj/project.xcproj")
        let root = ProjectLayout.canonical(project.root)
        project.write(Self.log.replacing("/p/", with: root + "/"), to: "build.log")
        return project
    }

    @Test func eachDiagnosticCountsOnceByGroupAndModule() async throws {
        let project = project()
        let report = try await ConcurrencyReport.read(log: project.root.appending(path: "build.log"), project: project, groups: { _ in .read(docs: nil) }, using: FakeRunner())
        #expect(report.count == 5)
        #expect(report.errors == 1)
        #expect(report.ungrouped == 1)
        #expect(report.groups.map { "\($0.name) \($0.count)" } == ["MutableGlobalVariable 3", "SendingRisksDataRace 2"])
        #expect(report.groups.first?.modules.map { "\($0.name) \($0.count)" } == ["App 1", "Feature 1", "Kit 1"])
        #expect(report.modules.map { "\($0.name) \($0.count)" } == ["Kit 2", "App 1", "Feature 1", "not in a project 1"])
    }

    /// A log read in pieces counts a line split between two the same as one read whole.
    @Test func aLogLargerThanOneReadIsReadWhole() async throws {
        let project = project()
        let padding = String(repeating: "note: nothing to see here\n", count: 80_000)
        let root = ProjectLayout.canonical(project.root)
        project.write(padding + Self.log.replacing("/p/", with: root + "/") + padding, to: "build.log")
        let report = try await ConcurrencyReport.read(log: project.root.appending(path: "build.log"), project: project, groups: { _ in .read(docs: nil) }, using: FakeRunner())
        #expect(report.count == 5)
    }

    func read(_ log: String, in project: Project, docs: @escaping @Sendable (URL?) -> ConcurrencyGroups = { _ in .read(docs: nil) }) async throws -> ConcurrencyReport {
        project.write(log, to: "build.log")
        return try await ConcurrencyReport.read(log: project.root.appending(path: "build.log"), project: project, groups: docs, using: FakeRunner())
    }

    /// The compiler writes a path as it was given; the project may be read through another spelling of its folder.
    @Test func aPathSpelledAnotherWayStillFindsItsModule() async throws {
        let project = project()
        #expect(project.root.path != project.canonicalRoot, "the temporary folder needs a second spelling for this test")
        let report = try await read(Self.log.replacing("/p/", with: project.root.path + "/"), in: project)
        #expect(report.modules.map(\.name) == ["Kit", "App", "Feature", "not in a project"])
    }

    /// A task's header names the target it compiles, a package's included, which no project file lists.
    @Test func theTaskHeaderNamesTheModule() async throws {
        let report = try await read("""
            SwiftCompile normal arm64 /pkg/Sources/Net/Net.swift (in target 'Net' from project 'Net')
                cd /pkg

            /pkg/Sources/Net/Net.swift:4:1: warning: var 'cache' is not concurrency-safe [#MutableGlobalVariable]

            """, in: project())
        #expect(report.modules.map(\.name) == ["Net"])
    }

    @Test func aLogWithWindowsLineEndingsIsRead() async throws {
        let project = project()
        let report = try await read(Self.log.replacing("/p/", with: project.canonicalRoot + "/").replacing("\n", with: "\r\n"), in: project)
        #expect(report.count == 5)
    }

    /// What carries no group is counted among the Swift diagnostics only: a clang warning has a flag, not a group.
    @Test func onlySwiftDiagnosticsCountAsUngrouped() async throws {
        let report = try await read("""
            /p/Legacy.m:3:1: warning: 'oldAPI' is deprecated [-Wdeprecated-declarations]
            /p/Kit.swift:9:16: warning: stored property 'box' has non-Sendable type 'Box'

            """, in: project())
        #expect(report.ungrouped == 1)
    }

    /// The groups come from the docs of the Xcode the log was built with, which may not be the selected one.
    @Test func theGroupsAreThoseOfTheXcodeTheLogNames() async throws {
        let asked = Mutex<URL?>(nil)
        _ = try await read("""
                /Applications/Xcode-26.4.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc -module-name Kit
            /p/Kit.swift:1:12: warning: var 'x' is not concurrency-safe [#MutableGlobalVariable]

            """, in: project()) { xcode in
            asked.withLock { $0 = xcode }
            return .read(docs: nil)
        }
        #expect(asked.withLock { $0 } == URL(fileURLWithPath: "/Applications/Xcode-26.4.app"))
    }

    /// `--changed` with no change git can read says so, rather than calling the whole build the branch's.
    @Test func changedLinesGitCantReadAreSaid() async throws {
        let project = project()
        project.write(Self.log.replacing("/p/", with: project.canonicalRoot + "/"), to: "build.log")
        let report = try await ConcurrencyReport.read(log: project.root.appending(path: "build.log"), project: project, groups: { _ in .read(docs: nil) }, onlyChanged: true, using: FakeRunner())
        #expect(report.inChangedLines == nil)
        #expect(report.changeUnread != nil)
    }
}
