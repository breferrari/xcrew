import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

@Suite struct ConfigWriterTests {
    let answers = ProfileAnswers(container: "App.xcworkspace", testSimulator: "iPhone 17", testScheme: "App")

    @Test func writesAndMarksTheConfig() async throws {
        let project = Project.temporary()
        #expect(try ConfigWriter.write(answers, to: project, now: Date()) == .written(backup: nil))
        #expect(FileManager.default.fileExists(atPath: project.managedMarker.path))
        #expect(try String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8).contains("iPhone 17"))
    }

    @Test func rewritesItsOwnConfig() async throws {
        let project = Project.temporary()
        _ = try ConfigWriter.write(answers, to: project, now: Date())
        var changed = answers
        changed.testSimulator = "iPhone 18"
        #expect(try ConfigWriter.write(changed, to: project, now: Date()) == .written(backup: nil))
        #expect(try String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8).contains("iPhone 18"))
    }

    /// A config 0.8.1 wrote has a schemeless `unit` profile active; rerunning setup replaces it without --force.
    @Test func aConfigAnOlderXcrewWroteIsReplaced() async throws {
        let project = Project.temporary()
        let old = "schemaVersion: 1\nsessionDefaultsProfiles:\n  unit:\n    workspacePath: '/work/App.xcworkspace'\n    simulatorName: 'iPhone 17'\nactiveSessionDefaultsProfile: unit\n"
        project.write(old, to: ".mobilebuildmcp/config.yaml")
        try ConfigWriter.fingerprint(Data(old.utf8)).write(to: project.managedMarker)
        let app = ProfileAnswers(container: "App.xcworkspace", testSimulator: "iPhone 17", appScheme: "App")
        #expect(try ConfigWriter.write(app, to: project, now: Date()) == .written(backup: nil))
        #expect(try String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8).hasSuffix("activeSessionDefaultsProfile: app\n"))
    }

    /// The doctor asks for a restart when xcrew's marker is newer than MobileBuildMCP; rewriting the same config mustn't move it.
    @Test func theSameConfigIsntWrittenAgain() async throws {
        let project = Project.temporary()
        _ = try ConfigWriter.write(answers, to: project, now: Date())
        let then = Date(timeIntervalSinceNow: -3600)
        for file in [project.mobileBuildMCPConfig, project.managedMarker] {
            try FileManager.default.setAttributes([.modificationDate: then], ofItemAtPath: file.path)
        }
        #expect(try ConfigWriter.write(answers, to: project, now: Date()) == .written(backup: nil))
        for file in [project.mobileBuildMCPConfig, project.managedMarker] {
            #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date == then)
        }
    }

    @Test func leavesAHandWrittenConfigAlone() async throws {
        let project = Project.temporary()
        project.write("mine: true\n", to: ".mobilebuildmcp/config.yaml")
        #expect(try ConfigWriter.write(answers, to: project, now: Date()) == .keptUnmanaged)
        #expect(try String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8) == "mine: true\n")
    }

    @Test func forceReplacesAHandWrittenConfigAndKeepsABackup() async throws {
        let project = Project.temporary()
        project.write("mine: true\n", to: ".mobilebuildmcp/config.yaml")
        guard case .written(let backup?) = try ConfigWriter.write(answers, to: project, force: true, now: Date()) else {
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
        _ = try ConfigWriter.write(answers, to: project, now: Date())
        let edited = try String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8) + "debuggerBackend: lldb-cli\n"
        try edited.write(to: project.mobileBuildMCPConfig, atomically: true, encoding: .utf8)

        #expect(try ConfigWriter.write(answers, to: project, now: Date()) == .keptEdited)
        #expect(try String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8) == edited)
    }

    @Test func forceReplacesAnEditedConfigAndKeepsABackup() throws {
        let project = Project.temporary()
        _ = try ConfigWriter.write(answers, to: project, now: Date())
        try "edited: true\n".write(to: project.mobileBuildMCPConfig, atomically: true, encoding: .utf8)
        guard case .written(let backup?) = try ConfigWriter.write(answers, to: project, force: true, now: Date()) else {
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
        #expect(try ConfigWriter.write(answers, to: project, now: Date()) == .written(backup: nil))
    }
}

/// What only a restart loads into a running MobileBuildMCP, apart from the session defaults a call can set.
@Suite struct ServerPartTests {
    let answers = ProfileAnswers(container: "App.xcworkspace", testSimulator: "iPhone 17", testScheme: "App")

    @Test func theServerPartLeavesTheSessionDefaultsOut() {
        let yaml = "schemaVersion: 1\nenabledWorkflows:\n  - simulator\ndebuggerBackend: lldb-cli\nsessionDefaultsProfiles:\n  unit:\n    scheme: 'App'\nactiveSessionDefaultsProfile: unit\nsessionDefaults:\n  simulatorName: 'iPhone 17'\nshowTestTiming: true\n"
        #expect(ConfigRenderer.serverPart(of: yaml) == "schemaVersion: 1\nenabledWorkflows:\n  - simulator\ndebuggerBackend: lldb-cli\nshowTestTiming: true\n")
    }

    /// A comment line ends no section: one between the profiles leaves them out of the server part with it, so a change
    /// to them asks for no restart. One among the server settings stays, as before.
    @Test func aCommentLineEndsNoSection() {
        let yaml = "schemaVersion: 1\n# the tool groups\nenabledWorkflows:\n  - simulator\nsessionDefaultsProfiles:\n  unit:\n    scheme: 'App'\n# the app\n  app:\n    scheme: 'App'\nactiveSessionDefaultsProfile: unit\nshowTestTiming: true\n"
        #expect(ConfigRenderer.serverPart(of: yaml) == "schemaVersion: 1\n# the tool groups\nenabledWorkflows:\n  - simulator\nshowTestTiming: true\n")
    }

    /// The server marker moves only when the server part does: a new simulator or scheme leaves it where it was.
    @Test func theServerMarkerMovesOnlyWithTheServerPart() throws {
        let project = Project.temporary()
        _ = try ConfigWriter.write(answers, to: project, now: Date())
        #expect(FileManager.default.fileExists(atPath: project.serverMarker.path))
        let then = Date(timeIntervalSinceNow: -3600)
        try FileManager.default.setAttributes([.modificationDate: then], ofItemAtPath: project.serverMarker.path)
        var changed = answers
        changed.testSimulator = "iPhone 18"
        _ = try ConfigWriter.write(changed, to: project, now: Date())
        #expect(try FileManager.default.attributesOfItem(atPath: project.serverMarker.path)[.modificationDate] as? Date == then)
        changed.debuggerBackend = "dap"
        _ = try ConfigWriter.write(changed, to: project, now: Date())
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
        #expect(LiveDefaults.calls(in: yaml, root: URL(fileURLWithPath: "/work/App"), home: URL(fileURLWithPath: "/home/someone")) == [
            #"session_set_defaults {"bundleId":"com.example.app","createIfNotExists":true,"profile":"app","scheme":"App","simulatorName":"iPhone 17","workspacePath":"/work/App/App.xcworkspace"}"#,
            #"session_set_defaults {"createIfNotExists":true,"env":{"LOG":"quiet"},"extraArgs":["-skipMacroValidation"],"profile":"unit","scheme":"AppTests","simulatorId":"AAAA","simulatorName":"iPhone 17","useLatestOS":true,"workspacePath":"/work/App/App.xcworkspace"}"#,
        ])
    }

    /// A path the config writes from the root as `./App.xcworkspace` is printed standardized, with no `/./`.
    @Test func aDotRelativePathIsStandardized() {
        let yaml = "schemaVersion: 1\nsessionDefaultsProfiles:\n  unit:\n    workspacePath: './App.generated.xcworkspace'\n    scheme: 'App'\nactiveSessionDefaultsProfile: unit\n"
        let calls = LiveDefaults.calls(in: yaml, root: URL(fileURLWithPath: "/work/App"), home: URL(fileURLWithPath: "/home/someone"))
        #expect(calls == [#"session_set_defaults {"createIfNotExists":true,"profile":"unit","scheme":"App","workspacePath":"/work/App/App.generated.xcworkspace"}"#])
    }

    /// A config's profiles as a person may write them: a name quoted, a comment line between profiles, a comment after a
    /// value, and a path from the home folder. Each reaches the running server as setup means it.
    @Test func aHandEditedConfigsProfilesAreReadAsSetupMeansThem() {
        let yaml = """
        schemaVersion: 1
        sessionDefaultsProfiles:
          'my app':
            workspacePath: '~/Work/App.xcworkspace'
            scheme: App # the app's own
        # the unit tests, kept apart
          unit:
            scheme: 'AppTests'
        activeSessionDefaultsProfile: 'my app'

        """
        #expect(LiveDefaults.calls(in: yaml, root: URL(fileURLWithPath: "/work/App"), home: URL(fileURLWithPath: "/home/someone")) == [
            #"session_set_defaults {"createIfNotExists":true,"profile":"unit","scheme":"AppTests"}"#,
            #"session_set_defaults {"createIfNotExists":true,"profile":"my app","scheme":"App","workspacePath":"/home/someone/Work/App.xcworkspace"}"#,
        ])
    }

    /// The calls for one profile `unit` holding `body`, active: what `LiveDefaults` sends for it.
    static func unitCall(_ body: String, indent: String = "  ") -> [String] {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map { indent + indent + $0 }.joined(separator: "\n")
        let yaml = "schemaVersion: 1\nsessionDefaultsProfiles:\n\(indent)unit:\n\(lines)\nactiveSessionDefaultsProfile: unit\n"
        return LiveDefaults.calls(in: yaml, root: URL(fileURLWithPath: "/work/App"), home: URL(fileURLWithPath: "/home/someone"))
    }

    /// A long value MobileBuildMCP's own `yaml.stringify` wraps at 80 columns goes on, indented, on the next line: YAML
    /// folds the two with one space.
    @Test func aWrappedValueIsReadWhole() {
        #expect(Self.unitCall("scheme: 'App'\nderivedDataPath: /build/Some Tool With A Long Name/That Wraps\n  Onto The Next Line/DerivedData") == [#"session_set_defaults {"createIfNotExists":true,"derivedDataPath":"/build/Some Tool With A Long Name/That Wraps Onto The Next Line/DerivedData","profile":"unit","scheme":"App"}"#])
    }

    /// A list's items may sit at their key's own indent, as YAML allows and a carried `extraArgs` may be written.
    @Test func aListAtItsKeysIndentIsRead() {
        #expect(Self.unitCall("scheme: 'App'\nextraArgs:\n- '-a'\n- '-b'") == [#"session_set_defaults {"createIfNotExists":true,"extraArgs":["-a","-b"],"profile":"unit","scheme":"App"}"#])
    }

    /// `yaml.stringify` writes an empty list or map inline, and a person may write a short list so.
    @Test func anInlineListOrMapIsReadAsOne() {
        #expect(Self.unitCall("scheme: 'App'\nextraArgs: []\nenv: {}") == [#"session_set_defaults {"createIfNotExists":true,"env":{},"extraArgs":[],"profile":"unit","scheme":"App"}"#])
        #expect(Self.unitCall("scheme: 'App'\nextraArgs: [-a, '-b']\nenv: {LOG: quiet}") == [#"session_set_defaults {"createIfNotExists":true,"env":{"LOG":"quiet"},"extraArgs":["-a","-b"],"profile":"unit","scheme":"App"}"#])
    }

    /// The active profile's line and a profile's own may carry a comment.
    @Test func aCommentAfterTheActiveProfileOrAProfilesNameIsLeftOut() {
        let yaml = "schemaVersion: 1\nsessionDefaultsProfiles:\n  unit: # the unit tests\n    scheme: 'AppTests'\n  app:\n    scheme: 'App'\nactiveSessionDefaultsProfile: unit # the default\n"
        #expect(LiveDefaults.calls(in: yaml, root: URL(fileURLWithPath: "/work/App"), home: URL(fileURLWithPath: "/home/someone")) == [
            #"session_set_defaults {"createIfNotExists":true,"profile":"app","scheme":"App"}"#,
            #"session_set_defaults {"createIfNotExists":true,"profile":"unit","scheme":"AppTests"}"#,
        ])
    }

    /// A config indented by four spaces reads as one indented by two.
    @Test func anyIndentIsRead() {
        #expect(Self.unitCall("scheme: 'App'\nextraArgs:\n    - '-a'", indent: "    ") == [#"session_set_defaults {"createIfNotExists":true,"extraArgs":["-a"],"profile":"unit","scheme":"App"}"#])
    }

    /// YAML's null, `~` and an empty value name none, so no key is sent for them; a quoted `true` is a string, and `True`
    /// a boolean, as YAML 1.2 reads them.
    @Test func nullsAreLeftOutAndBooleansAreReadAsYAMLReadsThem() {
        #expect(Self.unitCall("scheme: 'true'\nconfiguration: null\nbundleId: ~\nplatform:\nuseLatestOS: True") == [#"session_set_defaults {"createIfNotExists":true,"profile":"unit","scheme":"true","useLatestOS":true}"#])
    }

    /// A key whose value is on the lines below may carry a comment on its own line: its list or map is still read.
    @Test func aKeyWithACommentAndItsValueBelowIsRead() {
        #expect(Self.unitCall("scheme: 'App'\nenv: # launch vars\n  FOO: bar\nextraArgs: # flags\n- -quiet") == [#"session_set_defaults {"createIfNotExists":true,"env":{"FOO":"bar"},"extraArgs":["-quiet"],"profile":"unit","scheme":"App"}"#])
    }

    /// A profile's name may hold a colon, as `app:debug`: it's a profile of its own, not more of the one above it.
    @Test func aProfileNamedWithAColonIsAProfile() {
        let yaml = "schemaVersion: 1\nsessionDefaultsProfiles:\n  app:\n    scheme: 'App'\n  app:debug:\n    scheme: 'AppDebug'\nactiveSessionDefaultsProfile: app:debug\n"
        #expect(ConfigRenderer.profiles(in: yaml).names == ["app", "app:debug"])
        #expect(ConfigRenderer.schemeToBuild(in: yaml) == "AppDebug")
        #expect(LiveDefaults.calls(in: yaml, root: URL(fileURLWithPath: "/work/App"), home: URL(fileURLWithPath: "/home/someone")) == [
            #"session_set_defaults {"createIfNotExists":true,"profile":"app","scheme":"App"}"#,
            #"session_set_defaults {"createIfNotExists":true,"profile":"app:debug","scheme":"AppDebug"}"#,
        ])
    }

    /// A long value wrapped onto the next line, as MobileBuildMCP's `yaml.stringify` writes one past 80 columns, is
    /// read whole in a map, in a list, and as a profile's setting.
    @Test func aWrappedValueIsReadWholeEverywhere() {
        let body = "scheme: My App Scheme With A Name Long Enough\n  To Wrap\nenv:\n  LONG: a value long enough that it wraps\n    onto the next line\nextraArgs:\n- -an-argument long enough that it wraps\n  onto the next line"
        #expect(Self.unitCall(body) == [#"session_set_defaults {"createIfNotExists":true,"env":{"LONG":"a value long enough that it wraps onto the next line"},"extraArgs":["-an-argument long enough that it wraps onto the next line"],"profile":"unit","scheme":"My App Scheme With A Name Long Enough To Wrap"}"#])
        let yaml = "schemaVersion: 1\nsessionDefaultsProfiles:\n  unit:\n" + body.split(separator: "\n").map { "    " + $0 }.joined(separator: "\n") + "\nactiveSessionDefaultsProfile: unit\n"
        #expect(ConfigRenderer.schemeToBuild(in: yaml) == "My App Scheme With A Name Long Enough To Wrap")
    }

    /// The session defaults read as MobileBuildMCP reads them, by the installed MobileBuildMCP's own YAML library
    /// (`utils/project-config.js` parses the config with `yaml`), run with the Node it ships, wherever it's installed:
    /// each profile's keys and values alike, YAML's nulls left out, over every shape the reader takes.
    @Test(.enabled(if: RunLogWorkspaceTests.mobileBuildMCP != nil))
    func theProfilesAreReadAsTheInstalledMobileBuildMCPReadsThem() async throws {
        let libexec = try #require(RunLogWorkspaceTests.mobileBuildMCP)
        let yaml = """
        schemaVersion: 1
        sessionDefaultsProfiles:
            'my: app': # the app
                scheme: App # the app's own
                derivedDataPath: /build/Some Tool With A Long Name/That Wraps
                  Onto The Next Line/DerivedData
                extraArgs:
                - '-a'
                - "-b" # second
        # the unit tests
            unit:
                scheme: 'true'
                configuration: null
                bundleId: ~
                platform:
                useLatestOS: True
                extraArgs: [-a, '-b']
                env: {LOG: quiet}
            empty:
                extraArgs: []
                env: {}
            app:debug: # a colon in the name
                env: # launch vars
                    FOO: bar
                    LONG: a value long enough that it wraps
                      onto the next line
                extraArgs: # flags
                - -an-argument long enough that it wraps
                  onto the next line
        activeSessionDefaultsProfile: unit # the default

        """
        let script = "const y = require(process.argv[1]); const c = y.parse(require('fs').readFileSync(0, 'utf8')); console.log(JSON.stringify(c.sessionDefaultsProfiles))"
        let ran = await SystemCommandRunner().run([libexec.appending(path: "node-runtime").path, "-e", script, libexec.appending(path: "node_modules/yaml").path], stdin: Data(yaml.utf8), timeout: .seconds(30))
        let upstream = try #require(try JSONSerialization.jsonObject(with: Data(ran.stdout.utf8)) as? [String: [String: Any]], "MobileBuildMCP's yaml gave \(ran.stdout) \(ran.stderr)")
        let theirs = upstream.mapValues { $0.filter { !($0.value is NSNull) } }
        let ours = Dictionary(uniqueKeysWithValues: ConfigRenderer.sessions(in: yaml).profiles.map { ($0.name, LiveDefaults.defaults($0.lines, root: URL(fileURLWithPath: "/work/App"), home: URL(fileURLWithPath: "/home/someone"))) })
        #expect(Set(ours.keys) == Set(theirs.keys))
        for (name, values) in theirs {
            #expect(NSDictionary(dictionary: ours[name] ?? [:]) == NSDictionary(dictionary: values), "profile \(name): xcrew reads \(ours[name] ?? [:]), MobileBuildMCP's yaml \(values)")
        }
        #expect(ConfigRenderer.profiles(in: yaml).active == "unit")
    }

    @Test func globalDefaultsAreOneCallWithoutAProfile() {
        let yaml = "schemaVersion: 1\nsessionDefaults:\n  projectPath: '/abs/App.xcodeproj'\n  simulatorName: 'iPhone 17'\n"
        #expect(LiveDefaults.calls(in: yaml, root: URL(fileURLWithPath: "/work/App"), home: URL(fileURLWithPath: "/home/someone")) == [#"session_set_defaults {"projectPath":"/abs/App.xcodeproj","simulatorName":"iPhone 17"}"#])
    }
}
