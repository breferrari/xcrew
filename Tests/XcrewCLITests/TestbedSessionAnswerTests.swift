import Foundation
import Testing
import XcrewCLI
import XcrewTestSupport

/// The session tools' answers the mod's tests read (`hooks/mod/fixtures.ts`), copied from the test bed's raw captures:
/// each text is the capture's joined `content`, as Claude Code hands it, each JSON its `structuredContent`, and each
/// `…Read` what `xcrew session` answers for the text, which the mod's tests stub the CLI with.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedSessionAnswerTests {
    static let fixtures = Testbed.repository.appending(path: "hooks/mod/fixtures.ts")

    /// A `fixtures.ts` constant's text, written as a JSON string.
    static func fixture(_ name: String) throws -> String {
        let source = try String(contentsOf: fixtures, encoding: .utf8)
        let start = try #require(source.range(of: "export const \(name): Captured = {\n  isError: false,\n  text: "), "fixtures.ts has no \(name)").upperBound
        let end = try #require(source[start...].range(of: ",\n}\n")).lowerBound
        return try JSONDecoder().decode(String.self, from: Data(source[start..<end].utf8))
    }

    static func capture(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Testbed.root.appending(path: "captures/raw/\(name).json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test(arguments: [("mobileSessionDefaults", "session-defaults"), ("mobileProfileSwitched", "profile-switched")])
    func aFixturesTextIsItsCapturesContent(fixture: String, capture: String) throws {
        let parts = try #require(try Self.capture(capture)["content"] as? [[String: Any]])
        #expect(try Self.fixture(fixture) == parts.compactMap { $0["text"] as? String }.joined())
    }

    @Test(arguments: [("mobileSessionDefaults", "mobileSessionDefaultsRead"), ("mobileProfileSwitched", "mobileProfileSwitchedRead")])
    func aFixturesReadingIsWhatTheCLIAnswers(text: String, read: String) async throws {
        let run = await Run("session", stdin: try Self.fixture(text))
        #expect(run.status == 0)
        #expect(run.text == (try Self.fixture(read)))
    }

    /// The mod's stub answers `{}` for a text in no shape the CLI knows, as the CLI does.
    @Test func aTextInNoKnownShapeIsReadAsNothing() async {
        #expect(await Run("session", stdin: "\n⚙️ Show Defaults\n\nprofiles moved to a table\n").text == "{}")
    }

    @Test(arguments: [("mobileSessionDefaultsJSON", "session-defaults"), ("mobileProfileSwitchedJSON", "profile-switched")])
    func aFixturesJSONIsItsCapturesStructuredContent(fixture: String, capture: String) throws {
        let json = try #require(try JSONSerialization.jsonObject(with: Data(try Self.fixture(fixture).utf8)) as? NSDictionary)
        #expect(json == (try Self.capture(capture)["structuredContent"] as? NSDictionary))
    }
}
