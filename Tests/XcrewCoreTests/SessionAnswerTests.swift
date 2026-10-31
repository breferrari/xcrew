import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// MobileBuildMCP's session tools' text answers, read from the test bed's raw captures, and texts in other shapes.
struct SessionAnswerTests {
    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aListingGivesEachProfilesSchemeAndSimulatorAndNoneInUse() throws {
        #expect(SessionAnswer.read(try Raw.text("session-defaults")) == SessionAnswer(profiles: [
            "(default)": .init(),
            "probe": .init(scheme: "Feature", simulatorName: "xcrew-testbed"),
            "unit": .init(scheme: "Data", simulatorName: "xcrew-testbed"),
        ]))
    }

    @Test(.enabled(if: Testbed.isCheckedOut, "no test bed"))
    func aSwitchGivesTheProfileItActivated() throws {
        #expect(SessionAnswer.read(try Raw.text("profile-switched")) == SessionAnswer(currentProfile: "unit"))
    }

    @Test func theUnnamedProfileIsCalledAsTheListingCallsIt() {
        #expect(SessionAnswer.read("\n⚙️ Use Defaults Profile\n\n✅ Activated profile (default profile)\n") == SessionAnswer(currentProfile: "(default)"))
    }

    /// A text in another shape says nothing, so it changes nothing the mod knows.
    @Test(arguments: [
        "\n⚙️ Show Defaults\n\nprofiles moved to a table\n",
        "\n⚙️ Show Defaults\n\n📁 probe\n  ├ workspacePath: /w\n",
        "\n⚙️ Use Defaults Profile\n\n✅ Activated a new kind of profile\n",
        "📁 probe\n  ├ scheme: App\n  └ simulatorName: iPhone\n",
        "",
    ])
    func aTextInAnotherShapeSaysNothing(_ text: String) {
        #expect(SessionAnswer.read(text) == SessionAnswer())
    }
}
