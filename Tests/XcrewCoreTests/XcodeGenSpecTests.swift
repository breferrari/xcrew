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

    @Test func anIncludeKeyBelowTheTopIsntTheSpecs() {
        #expect(XcodeGenSpec.includes(in: "targets:\n  App:\n    include: a.yml\n") == [])
    }
}
