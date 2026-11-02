import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

@Suite struct ConfigWriterTests {
    let answers = ProfileAnswers(container: "App.xcworkspace", testSimulator: "iPhone 17", testScheme: "App")

    @Test func writesAndMarksTheConfig() async throws {
        let project = Project.temporary()
        #expect(try ConfigWriter.write(answers, to: project) == .written(backup: nil))
        #expect(FileManager.default.fileExists(atPath: project.managedMarker.path))
        #expect(try String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8).contains("iPhone 17"))
    }

    @Test func rewritesItsOwnConfig() async throws {
        let project = Project.temporary()
        _ = try ConfigWriter.write(answers, to: project)
        var changed = answers
        changed.testSimulator = "iPhone 18"
        #expect(try ConfigWriter.write(changed, to: project) == .written(backup: nil))
        #expect(try String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8).contains("iPhone 18"))
    }

    /// A config 0.8.1 wrote has a schemeless `unit` profile active; rerunning setup replaces it without --force.
    @Test func aConfigAnOlderXcrewWroteIsReplaced() async throws {
        let project = Project.temporary()
        let old = "schemaVersion: 1\nsessionDefaultsProfiles:\n  unit:\n    workspacePath: '/work/App.xcworkspace'\n    simulatorName: 'iPhone 17'\nactiveSessionDefaultsProfile: unit\n"
        project.write(old, to: ".mobilebuildmcp/config.yaml")
        try ConfigWriter.fingerprint(Data(old.utf8)).write(to: project.managedMarker)
        let app = ProfileAnswers(container: "App.xcworkspace", testSimulator: "iPhone 17", appScheme: "App")
        #expect(try ConfigWriter.write(app, to: project) == .written(backup: nil))
        #expect(try String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8).hasSuffix("activeSessionDefaultsProfile: app\n"))
    }

    /// The doctor asks for a restart when xcrew's marker is newer than MobileBuildMCP; rewriting the same config mustn't move it.
    @Test func theSameConfigIsntWrittenAgain() async throws {
        let project = Project.temporary()
        _ = try ConfigWriter.write(answers, to: project)
        let then = Date(timeIntervalSinceNow: -3600)
        for file in [project.mobileBuildMCPConfig, project.managedMarker] {
            try FileManager.default.setAttributes([.modificationDate: then], ofItemAtPath: file.path)
        }
        #expect(try ConfigWriter.write(answers, to: project) == .written(backup: nil))
        for file in [project.mobileBuildMCPConfig, project.managedMarker] {
            #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date == then)
        }
    }

    @Test func leavesAHandWrittenConfigAlone() async throws {
        let project = Project.temporary()
        project.write("mine: true\n", to: ".mobilebuildmcp/config.yaml")
        #expect(try ConfigWriter.write(answers, to: project) == .keptUnmanaged)
        #expect(try String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8) == "mine: true\n")
    }

    @Test func forceReplacesAHandWrittenConfigAndKeepsABackup() async throws {
        let project = Project.temporary()
        project.write("mine: true\n", to: ".mobilebuildmcp/config.yaml")
        guard case .written(let backup?) = try ConfigWriter.write(answers, to: project, force: true) else {
            Issue.record("expected a backup")
            return
        }
        #expect(try String(contentsOf: backup, encoding: .utf8) == "mine: true\n")
    }
}

@Suite struct HandEditedConfigTests {
    let answers = ProfileAnswers(container: "App.xcworkspace", testSimulator: "iPhone 17", testScheme: "App")

    @Test func aManagedConfigEditedByHandIsKept() throws {
        let project = Project.temporary()
        _ = try ConfigWriter.write(answers, to: project)
        let edited = try String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8) + "debuggerBackend: lldb-cli\n"
        try edited.write(to: project.mobileBuildMCPConfig, atomically: true, encoding: .utf8)

        #expect(try ConfigWriter.write(answers, to: project) == .keptEdited)
        #expect(try String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8) == edited)
    }

    @Test func forceReplacesAnEditedConfigAndKeepsABackup() throws {
        let project = Project.temporary()
        _ = try ConfigWriter.write(answers, to: project)
        try "edited: true\n".write(to: project.mobileBuildMCPConfig, atomically: true, encoding: .utf8)
        guard case .written(let backup?) = try ConfigWriter.write(answers, to: project, force: true) else {
            Issue.record("expected a backup")
            return
        }
        #expect(try String(contentsOf: backup, encoding: .utf8) == "edited: true\n")
    }

    @Test func aConfigFromAnEarlierXcrewIsStillUpdated() throws {
        // Earlier versions left the marker empty.
        let project = Project.temporary()
        project.write("old: true\n", to: ".mobilebuildmcp/config.yaml")
        try Data().write(to: project.managedMarker)
        #expect(try ConfigWriter.write(answers, to: project) == .written(backup: nil))
    }
}

/// What only a restart loads into a running MobileBuildMCP, apart from the session defaults a call can set.
@Suite struct ServerPartTests {
    let answers = ProfileAnswers(container: "App.xcworkspace", testSimulator: "iPhone 17", testScheme: "App")

    @Test func theServerPartLeavesTheSessionDefaultsOut() {
        let yaml = "schemaVersion: 1\nenabledWorkflows:\n  - simulator\ndebuggerBackend: lldb-cli\nsessionDefaultsProfiles:\n  unit:\n    scheme: 'App'\nactiveSessionDefaultsProfile: unit\nsessionDefaults:\n  simulatorName: 'iPhone 17'\nshowTestTiming: true\n"
        #expect(ConfigRenderer.serverPart(of: yaml) == "schemaVersion: 1\nenabledWorkflows:\n  - simulator\ndebuggerBackend: lldb-cli\nshowTestTiming: true\n")
    }

    /// The server marker moves only when the server part does: a new simulator or scheme leaves it where it was.
    @Test func theServerMarkerMovesOnlyWithTheServerPart() throws {
        let project = Project.temporary()
        _ = try ConfigWriter.write(answers, to: project)
        #expect(FileManager.default.fileExists(atPath: project.serverMarker.path))
        let then = Date(timeIntervalSinceNow: -3600)
        try FileManager.default.setAttributes([.modificationDate: then], ofItemAtPath: project.serverMarker.path)
        var changed = answers
        changed.testSimulator = "iPhone 18"
        _ = try ConfigWriter.write(changed, to: project)
        #expect(try FileManager.default.attributesOfItem(atPath: project.serverMarker.path)[.modificationDate] as? Date == then)
        changed.debuggerBackend = "dap"
        _ = try ConfigWriter.write(changed, to: project)
        #expect((try FileManager.default.attributesOfItem(atPath: project.serverMarker.path)[.modificationDate] as? Date ?? then) > then)
    }
}

/// The calls that give this session's MobileBuildMCP setup's profiles without a restart.
@Suite struct LiveDefaultsTests {
    @Test func eachProfileIsOneCallTheActiveLast() {
        let yaml = """
        schemaVersion: 1
        enabledWorkflows:
          - simulator
        sessionDefaultsProfiles:
          unit:
            workspacePath: 'App.xcworkspace'
            scheme: 'AppTests'
            simulatorName: 'iPhone 17'
            simulatorId: 'AAAA'
            env:
              LOG: 'quiet'
            extraArgs:
              - '-skipMacroValidation'
            useLatestOS: true
          app:
            workspacePath: 'App.xcworkspace'
            scheme: 'App'
            simulatorName: 'iPhone 17'
            bundleId: 'com.example.app'
        activeSessionDefaultsProfile: unit

        """
        #expect(LiveDefaults.calls(in: yaml, root: URL(fileURLWithPath: "/work/App")) == [
            #"session_set_defaults {"bundleId":"com.example.app","createIfNotExists":true,"profile":"app","scheme":"App","simulatorName":"iPhone 17","workspacePath":"/work/App/App.xcworkspace"}"#,
            #"session_set_defaults {"createIfNotExists":true,"env":{"LOG":"quiet"},"extraArgs":["-skipMacroValidation"],"profile":"unit","scheme":"AppTests","simulatorId":"AAAA","simulatorName":"iPhone 17","useLatestOS":true,"workspacePath":"/work/App/App.xcworkspace"}"#,
        ])
    }

    @Test func globalDefaultsAreOneCallWithoutAProfile() {
        let yaml = "schemaVersion: 1\nsessionDefaults:\n  projectPath: '/abs/App.xcodeproj'\n  simulatorName: 'iPhone 17'\n"
        #expect(LiveDefaults.calls(in: yaml, root: URL(fileURLWithPath: "/work/App")) == [#"session_set_defaults {"projectPath":"/abs/App.xcodeproj","simulatorName":"iPhone 17"}"#])
    }
}
