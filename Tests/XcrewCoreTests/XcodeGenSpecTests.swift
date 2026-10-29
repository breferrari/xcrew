import Foundation
import Testing
@testable import XcrewCore

/// The `include` key of an XcodeGen spec, in each form XcodeGen's ProjectSpec documents.
@Suite struct XcodeGenSpecTests {
    @Test func aSingleIncludeIsAPath() {
        #expect(XcodeGenSpec.includes(in: "name: App\ninclude: targets/App.yml\n") == [.init(path: "targets/App.yml")])
    }

    @Test func aFlowListIsEachOfItsPaths() {
        #expect(XcodeGenSpec.includes(in: "include: [a.yml, \"b c.yml\", 'd.yml']\nname: App\n") == [.init(path: "a.yml"), .init(path: "b c.yml"), .init(path: "d.yml")])
    }

    @Test func aBlockListTakesPathsAndObjects() {
        let spec = """
            name: App
            include:
              - a.yml # the targets
              - path: b.yml
                relativePaths: false
              - path: c.yml
                enable: false
            targets:
              App:
                type: application
            """
        #expect(XcodeGenSpec.includes(in: spec) == [.init(path: "a.yml"), .init(path: "b.yml", relativePaths: false), .init(path: "c.yml", enable: false)])
    }

    /// What xcrew can't know at edit time is left out rather than guessed: a variable the loader expands from the
    /// environment, or an `enable` that isn't a literal.
    @Test func anIncludeItCantResolveIsLeftOut() {
        let spec = """
            include:
              - ${SPECS}/a.yml
              - path: b.yml
                enable: ${WITH_B}
              - c.yml
            """
        #expect(XcodeGenSpec.includes(in: spec) == [.init(path: "c.yml")])
    }

    /// YAML allows a block list at its key's own indent, and a comment after the key.
    @Test func aCompactListAfterACommentIsRead() {
        #expect(XcodeGenSpec.includes(in: "include: # shared specs\n- a.yml\n- b.yml\nname: App\n") == [.init(path: "a.yml"), .init(path: "b.yml")])
    }

    @Test func flowMappingsAndAListAcrossLinesAreRead() {
        #expect(XcodeGenSpec.includes(in: "include: {path: a.yml, relativePaths: false}\n") == [.init(path: "a.yml", relativePaths: false)])
        #expect(XcodeGenSpec.includes(in: "include:\n  - {path: b.yml, enable: false}\n  - c.yml\n") == [.init(path: "b.yml", enable: false), .init(path: "c.yml")])
        #expect(XcodeGenSpec.includes(in: "include: [\n  a.yml,\n  b.yml\n]\nname: App\n") == [.init(path: "a.yml"), .init(path: "b.yml")])
    }

    /// XcodeGen reads a flag as a YAML boolean, in the words its YAML library takes, or as `NSString.boolValue` reads
    /// other text; a number is neither, and the flag keeps its default (docs/findings.md, *XcodeGen's included specs*).
    @Test(arguments: [("on", true), ("Yes", true), ("y", true), ("off", false), ("n", false), ("maybe", false), ("0", true), ("1", true)])
    func aFlagIsReadAsXcodeGenReadsIt(text: String, enabled: Bool) {
        #expect(XcodeGenSpec.includes(in: "include:\n  - path: a.yml\n    enable: \(text)\n") == [.init(path: "a.yml", enable: enabled)])
    }

    @Test func anIncludeKeyBelowTheTopIsntTheSpecs() {
        #expect(XcodeGenSpec.includes(in: "targets:\n  App:\n    include: a.yml\n") == [])
    }
}
