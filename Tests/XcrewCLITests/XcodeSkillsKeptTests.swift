import Foundation
import Testing
@testable import XcrewCLI

/// `xcrew xcode-skills` keeps a project's own skill of the same name; `--force` deletes it for Xcode's, with no copy kept.
@Suite struct XcodeSkillsKeptTests {
    @Test func keptSkillsSayReplacingThemLosesTheProjectsOwn() {
        #expect(XcodeSkillsCommand.kept(["swiftui", "testing"]) == "xcrew: kept the project's own swiftui, testing. Replacing them loses the project's own versions, so it's the person's to agree to: xcrew xcode-skills --force swiftui testing")
    }

    /// A name that isn't one shell word is quoted, so the command still runs as printed.
    @Test func aKeptNameWithASpaceIsQuoted() {
        #expect(XcodeSkillsCommand.kept(["my skill"]).hasSuffix(": xcrew xcode-skills --force 'my skill'"))
    }
}
