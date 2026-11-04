import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

@Suite struct XcodeSkillsTests {
    /// A stand-in for Xcode's plugin folder: two skills and a folder that isn't one.
    func xcodePlugin() -> Project {
        let plugin = Project.temporary()
        plugin.write("# A", to: "skills/swiftui-specialist/SKILL.md")
        plugin.write("# B", to: "skills/device-interaction/SKILL.md")
        plugin.write("", to: "skills/notes/readme.txt")
        return plugin
    }

    /// A Mac whose Xcode's plugin is `plugin`, as `runner` names it.
    func machine(_ runner: FakeRunner, _ plugin: Project) -> Machine {
        Machine(environment: [:], home: plugin.root.appending(path: "home"), runner: runner, files: RootedFiles(roots: [plugin.root]))
    }

    func runner(for plugin: Project) -> FakeRunner {
        FakeRunner(responses: ["xcrun mcpbridge run-agent plugin path --plugin-format claude": .init(status: 0, stdout: "note\n\(plugin.root.path)\n")])
    }

    @Test func findsTheSkillsTheInstalledXcodeShips() async throws {
        let plugin = xcodePlugin()
        let skills = try #require(await XcodeSkills.locate(on: machine(runner(for: plugin), plugin)))
        #expect(skills.available == ["device-interaction", "swiftui-specialist"])
    }

    @Test func noPluginBeforeXcode27() async {
        #expect(await XcodeSkills.locate(on: machine(FakeRunner(), Project.temporary())) == nil)
    }

    @Test func copiesAllOrTheNamedOnes() async throws {
        let plugin = xcodePlugin()
        let skills = try #require(await XcodeSkills.locate(on: machine(runner(for: plugin), plugin)))
        let project = Project.temporary()
        #expect(try skills.copy(["swiftui-specialist", "not-shipped"], to: project.skillsFolder) == .init(copied: ["swiftui-specialist"]))
        #expect(try skills.copy(to: project.skillsFolder) == .init(copied: ["device-interaction"], kept: ["swiftui-specialist"]))
    }

    @Test func aSkillAlreadyInTheProjectIsKeptUnlessReplaced() async throws {
        let plugin = xcodePlugin()
        let skills = try #require(await XcodeSkills.locate(on: machine(runner(for: plugin), plugin)))
        let project = Project.temporary()
        project.write("the team's own", to: ".claude/skills/swiftui-specialist/SKILL.md")
        let skill = project.skillsFolder.appending(path: "swiftui-specialist/SKILL.md")

        #expect(try skills.copy(["swiftui-specialist"], to: project.skillsFolder) == .init(kept: ["swiftui-specialist"]))
        #expect(try String(contentsOf: skill, encoding: .utf8) == "the team's own")

        #expect(try skills.copy(["swiftui-specialist"], to: project.skillsFolder, replacing: true) == .init(copied: ["swiftui-specialist"]))
        #expect(try String(contentsOf: skill, encoding: .utf8) == "# A")
    }
}
