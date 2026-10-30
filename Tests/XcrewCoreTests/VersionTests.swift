import Testing
@testable import XcrewCore
import XcrewTestSupport

@Suite struct VersionTests {
    @Test(arguments: [("2.7.1", "2.7.1", false), ("2.7.0", "2.7.1", true), ("2.10", "2.9.9", false), ("2.7", "2.7.0", false)])
    func ordering(left: String, right: String, isLess: Bool) {
        #expect((Version(left) < Version(right)) == isLess)
    }

    @Test func tolerantOfNoise() async {
        #expect(Version("v2.7.1\n") == Version("2.7.1"))
    }

    /// A beta's `b<n>`, as `.xcode-version` writes one, is no part of the number: `27.2b3` is 27.2, not 27.23.
    @Test func aBetaSuffixIsNoPartOfTheNumber() {
        #expect(Version("27.2b3") == Version("27.2"))
        #expect(Version("27.2b3") < Version("27.3"))
    }
}
