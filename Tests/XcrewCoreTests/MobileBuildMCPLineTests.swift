import Testing
@testable import XcrewCore

/// How MobileBuildMCP's text lines are read.
@Suite struct MobileBuildMCPLineTests {
    /// A repeated run's Test Results line, once `listingRunsOnce` counts its runs, still names the test it lists passed.
    @Test func aRepeatedRunsPassedLineNamesItsTest() {
        #expect(MobileBuildMCPLine.passed("  ✅ ProbeTests/testPasses(): passed 5 of 5 runs") == TestID(suite: "ProbeTests", name: "testPasses"))
        #expect(MobileBuildMCPLine.passed("  ✅ ProbeTests/testPasses (0.000s)") == TestID(suite: "ProbeTests", name: "testPasses"))
    }
}
