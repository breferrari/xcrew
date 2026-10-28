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

    func matches(_ pattern: String, _ name: String) -> Bool {
        name.range(of: "^(?:\(pattern))$", options: .regularExpression) != nil
    }

    /// Xcode MCP tool names under both registrations: the plugin's server, and a user's own
    /// local `xcode` server, which Claude Code prefers when both run the same command.
    func bothRegistrations(_ tool: String) -> [String] {
        ["mcp__xcode__\(tool)", "mcp__plugin_xcrew_xcode__\(tool)"]
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

    @Test func repairHookCoversEveryRepairableToolUnderBothRegistrations() async throws {
        let failure = try hook("PostToolUseFailure")
        #expect(failure.command == #""${CLAUDE_PLUGIN_ROOT}/bin/xcrew" hook repair-macros"#)
        let matcher = try #require(failure.matcher)
        for tool in try modRepairableTools() {
            for name in bothRegistrations(tool) { #expect(matches(matcher, name), "\(name)") }
        }
        #expect(!matches(matcher, "mcp__xcode__XcodeRead"))
        #expect(!matches(matcher, "mcp__plugin_other_xcode__BuildProject"))
    }

    @Test func buildLogHookCoversBothRegistrations() async throws {
        let matcher = try #require(try hook("PostToolUse").matcher)
        for name in bothRegistrations("GetBuildLog") { #expect(matches(matcher, name)) }
    }

    @Test func hooksLoadTheMod() async throws {
        let modules = try #require(try json("hooks/hooks.json")["modules"] as? [String])
        #expect(modules == ["./mod/register.ts"])
        #expect(FileManager.default.fileExists(atPath: Self.repository.appending(path: "hooks/mod/register.ts").path))
    }

    /// The tool names the mod repairs and retries, read from `hooks/mod/tools.ts`.
    func modRepairableTools() throws -> [String] {
        let source = try text("hooks/mod/tools.ts")
        let list = try #require(source.range(of: #"REPAIRABLE_XCODE_TOOLS = \[[^\]]*\]"#, options: .regularExpression))
        return source[list].matches(of: /'(\w+)'/).map { String($0.1) }
    }

    @Test func modAndHookRepairTheSameTools() async throws {
        let tools = try modRepairableTools()
        #expect(!tools.isEmpty)
        let matcher = try #require(try hook("PostToolUseFailure").matcher)
        let alternation = try #require(matcher.firstMatch(of: /__\(([\w|]+)\)$/)).1
        #expect(Set(alternation.split(separator: "|").map(String.init)) == Set(tools))
    }

    @Test func modAndHookLookForTheSameFailure() throws {
        let source = try text("hooks/mod/repair.ts")
        let constant = try #require(source.firstMatch(of: /MACRO_PLUGIN_KILLED = '([^']+)'/)).1
        #expect(String(constant) == HookEvent.killedMacroPluginSignature)
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

    @Test func everyDoctorCheckIsAnMCSCheck() async throws {
        let techpack = try text("techpack.yaml")
        let listed = techpack.matches(of: /command: (mcs\/checks\/[\w.-]+\.sh)/).map { String($0.1) }
        #expect(listed.count == Doctor.checks.count)
        for check in Doctor.checks {
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
