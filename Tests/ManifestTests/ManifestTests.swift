import Foundation
import Testing
@testable import XcrewCLI
import XcrewCore

/// The plugin, the mcs techpack and the Swift code each name the same things: hooks, tools,
/// checks, prompts. These tests keep them in step, so a change in one place can't leave another
/// install path silently stale.
@Suite struct ManifestTests {
    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func text(_ path: String) throws -> String {
        try String(contentsOf: Self.repository.appending(path: path), encoding: .utf8)
    }

    func json(_ path: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text(path).utf8)) as? [String: Any])
    }

    // MARK: Commands

    /// A skill named like the plugin takes the bare `/<plugin>` command, and Claude Code then
    /// refuses the mod's `$.command.register` for it at every session start.
    @Test func noSkillTakesTheModsCommand() throws {
        let plugin = try #require(try json(".claude-plugin/plugin.json")["name"] as? String)
        let skills = try FileManager.default.contentsOfDirectory(atPath: Self.repository.appending(path: "skills").path)
        #expect(!skills.contains(plugin))
        let mod = try text("hooks/mod/command.ts")
        #expect(mod.contains("name: '\(plugin)'"))
    }

    // MARK: Plugin hooks

    /// The spinner text reads like the rest of Claude Code; the hook's name already says it's Xcrew's.
    @Test func hookSpinnersCarryNoPrefix() throws {
        let hooks = try #require(try json("hooks/hooks.json")["hooks"] as? [String: [[String: Any]]])
        let messages = hooks.values.flatMap { $0 }.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }.compactMap { $0["statusMessage"] as? String }
        #expect(!messages.isEmpty)
        #expect(messages.allSatisfy { !$0.hasPrefix("xcrew:") && $0.first?.isUppercase == true })
    }

    func hook(_ event: String) throws -> (matcher: String?, command: String) {
        let hooks = try #require(try json("hooks/hooks.json")["hooks"] as? [String: [[String: Any]]])
        let group = try #require(hooks[event]?.first)
        let handler = try #require((group["hooks"] as? [[String: Any]])?.first)
        return (group["matcher"] as? String, try #require(handler["command"] as? String))
    }

    @Test func sessionStartBriefsThroughTheCLI() async throws {
        #expect(try hook("SessionStart").command == #""${CLAUDE_PLUGIN_ROOT}/bin/xcrew" hook session-start"#)
    }

    @Test func sessionStartIsTheOnlyCommandHook() async throws {
        let hooks = try #require(try json("hooks/hooks.json")["hooks"] as? [String: Any])
        #expect(Array(hooks.keys) == ["SessionStart"])
    }

    @Test func hooksLoadTheMod() async throws {
        let modules = try #require(try json("hooks/hooks.json")["modules"] as? [String])
        #expect(modules == ["./mod/register.ts"])
        #expect(FileManager.default.fileExists(atPath: Self.repository.appending(path: "hooks/mod/register.ts").path))
    }

    /// mcs reads `techpack.yaml` strictly: a plain value holding `: ` is not valid YAML, and the whole
    /// pack fails to load. CI has no mcs to validate with, so this catches the usual way it breaks.
    @Test func techpackValuesWithAColonAreQuoted() throws {
        let unquoted = try text("techpack.yaml").components(separatedBy: "\n").filter {
            $0.contains(#/^\s*(?:- )?[\w-]+: (?!["'|>]).*: /#)
        }
        #expect(unquoted == [])
    }

    // MARK: MCP servers

    @Test func pluginShipsTheThreeServers() async throws {
        let servers = try #require(try json(".mcp.json")["mcpServers"] as? [String: [String: Any]])
        #expect(Set(servers.keys) == ["MobileBuildMCP", "xcode", "sosumi"])

        let mobile = try #require(servers["MobileBuildMCP"])
        let arguments = try #require(mobile["args"] as? [String])
        #expect(arguments.contains("${CLAUDE_PROJECT_DIR}"), "MobileBuildMCP reads its config from its working directory")
        #expect((mobile["env"] as? [String: String])?["MOBILEBUILDMCP_SENTRY_DISABLED"] == "true")

        #expect(servers["xcode"]?["command"] as? String == "xcrun")
        #expect(servers["xcode"]?["args"] as? [String] == ["mcpbridge"])
        #expect(servers["sosumi"]?["url"] as? String == "https://sosumi.ai/mcp")
    }

    // MARK: mcs techpack

    /// Checks the techpack leaves out because mcs does the same itself: `mcs check-updates` says when a
    /// pack has a newer version, with `mcs update` as the fix.
    static let coveredByMCS: Set = ["xcrew/up-to-date"]

    @Test func everyDoctorCheckIsAnMCSCheck() async throws {
        let techpack = try text("techpack.yaml")
        let listed = techpack.matches(of: /command: (mcs\/checks\/[\w.-]+\.sh)/).map { String($0.1) }
        let checks = Doctor.checks.filter { !Self.coveredByMCS.contains($0.id) }
        #expect(listed.count == checks.count)
        for check in Doctor.checks where Self.coveredByMCS.contains(check.id) {
            let wrapper = "mcs/checks/\(check.id.replacingOccurrences(of: "/", with: "--")).sh"
            #expect(!listed.contains(wrapper), "\(check.id): mcs does this itself, so the techpack leaves it out")
            #expect(!FileManager.default.fileExists(atPath: Self.repository.appending(path: wrapper).path), "\(wrapper)")
        }
        for check in checks {
            let wrapper = "mcs/checks/\(check.id.replacingOccurrences(of: "/", with: "--")).sh"
            #expect(listed.contains(wrapper), "\(check.id) missing from techpack.yaml")
            #expect(FileManager.default.isExecutableFile(atPath: Self.repository.appending(path: wrapper).path), "\(wrapper)")
            #expect(try text(wrapper).contains("doctor --check \(check.id)\n"), "\(wrapper)")
        }
    }

    /// mcs asks only for the workspace; the simulator defaults to the newest iPhone, and the
    /// schemes are found by `/xcrew:setup` instead of typed in.
    @Test func mcsAsksOnlyForTheWorkspace() async throws {
        let keys = try text("techpack.yaml").matches(of: /- key: (\w+)/).map { String($0.1) }
        #expect(keys == ["PROJECT"])
        #expect(Set(keys).isSubset(of: Set(SetupCommand.mcsKeys.values)), "a prompt no setup option reads")
    }

    @Test func mcsConfiguresThroughTheCLI() async throws {
        let techpack = try text("techpack.yaml")
        #expect(techpack.contains("script: mcs/configure.sh"))
        #expect(try text("mcs/configure.sh").contains("bin/xcrew\" setup"))
        #expect(techpack.contains("brew: getsentry/xcodebuildmcp/mobilebuildmcp"))
        #expect(techpack.contains("plugin: \"xcrew@"))
    }

    // MARK: Plugin identity

    @Test func oneVersionEverywhere() throws {
        let version = XcrewVersion.current
        #expect(try json(".claude-plugin/plugin.json")["version"] as? String == version)
        #expect(try text("CHANGELOG.md").contains("\n## \(version)"))
    }

    @Test func pluginAndMarketplaceAgree() async throws {
        #expect(try json(".claude-plugin/plugin.json")["name"] as? String == "xcrew")
        let plugins = try #require(try json(".claude-plugin/marketplace.json")["plugins"] as? [[String: Any]])
        #expect(plugins.map { $0["name"] as? String } == ["xcrew"])
        #expect(plugins.first?["source"] as? String == "./")
    }
}

/// The mod's boundary (docs/architecture.md, *The mod's boundary*): it hooks, draws, keeps state
/// and times calls, and hands everything it reads to the Swift CLI. These fail when logic drifts
/// back into TypeScript.
@Suite struct ModBoundaryTests {
    /// The mod's own sources: tests and their fixtures and helpers aren't the mod.
    static func sources() throws -> [(name: String, text: String)] {
        let folder = ManifestTests.repository.appending(path: "hooks/mod")
        return try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
            .filter { $0.hasSuffix(".ts") && !$0.hasSuffix(".test.ts") && !["fixtures.ts", "testing.ts"].contains($0) }
            .map { ($0, try String(contentsOf: folder.appending(path: $0), encoding: .utf8)) }
    }

    /// Files using `pattern` other than those allowed it.
    static func offenders(_ pattern: some RegexComponent, allowed: Set<String>) throws -> [String] {
        try sources().filter { !allowed.contains($0.name) && $0.text.contains(pattern) }.map(\.name)
    }

    @Test func onlyTheCLIWrapperRunsProcesses() throws {
        #expect(try Self.offenders(/\$\.process\./, allowed: ["cli.ts"]) == [])
    }

    /// Reading named fields of a server's JSON answer is fine where the mod keeps what it learns; parsing text isn't.
    @Test func onlyTheCLIWrapperAndContextReadJSON() throws {
        #expect(try Self.offenders(/JSON\.parse\(/, allowed: ["cli.ts", "context.ts"]) == [])
    }

    @Test func theModStartsOnlyTheCLIFromOnePlace() throws {
        let wrapper = try #require(try Self.sources().first { $0.name == "cli.ts" }).text
        // One call site, in `start`, which runs nothing but the shim or the build the shim names.
        #expect(wrapper.matches(of: /\$\.process\.run\(/).count == 1)
        let programs = Set(wrapper.matches(of: /start\(\$, ([^,]+),/).map { String($0.1) })
        #expect(programs == ["shim($)", "binary"])
        #expect(wrapper.contains("const binary = await build("))
    }

    @Test func onlyToolNamesAreMatchedByPattern() throws {
        #expect(try Self.offenders(/\.exec\(|\.test\(|\.match\(|\.matchAll\(|new RegExp|\.replace\(\//, allowed: ["tools.ts"]) == [])
    }

    @Test func theModTouchesNoFiles() throws {
        #expect(try Self.offenders(/\$\.fs\./, allowed: []) == [])
    }
}
