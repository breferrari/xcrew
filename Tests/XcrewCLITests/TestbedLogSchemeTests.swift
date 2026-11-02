import Foundation
import Testing
import XcrewTestSupport

/// What the mod asks of a running or backgrounded MobileBuildMCP call's log, and the scheme it names, on the test bed's
/// real serial run.
@Suite(.enabled(if: Testbed.isCheckedOut, "no test bed"))
struct TestbedLogSchemeTests {
    static let log = Testbed.root.appending(path: "captures/raw/serial.log").path

    @Test func thePhaseNamesTheSchemeTheLogBuilt() async throws {
        let run = await Run("phase", "--tool", "test_sim", "--since", "0", "--log", Self.log)
        let answer = try #require(try JSONSerialization.jsonObject(with: Data(run.text.utf8)) as? [String: Any])
        #expect(answer["scheme"] as? String == "Feature")
    }

    @Test func aReportReadFromTheLogNamesItsScheme() async throws {
        let run = await Run("report", "--server", "MobileBuildMCP", "--kind", "test", "--log", Self.log)
        let answer = try #require(try JSONSerialization.jsonObject(with: Data(run.text.utf8)) as? [String: Any])
        #expect(answer["scheme"] as? String == "Feature")
    }
}
