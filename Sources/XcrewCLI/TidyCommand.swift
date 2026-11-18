import Foundation
import XcrewCore

/// `xcrew tidy`: the mod runs it after each MobileBuildMCP test run. Once setup recorded `--finished-test-bundles drop`,
/// it deletes this checkout's finished test-run bundles but the newest (`FinishedTestBundles`); otherwise it deletes nothing.
struct TidyCommand: Command {
    let name = "tidy"
    let usage = ["tidy   (mod) once setup chose to drop finished test bundles, deletes this checkout's finished MobileBuildMCP test-run bundles but the newest; how many, as JSON"]

    struct Answer: Codable, Equatable {
        let dropped: Int
    }

    func run(_ invocation: Invocation) async throws -> Int32 {
        let context = invocation.context
        let chosen = await FinishedTestBundlesChoice.read(for: context.project, using: context.runner)
        let dropped = chosen == .drop ? FinishedTestBundles.drop(project: context.project, home: context.machine.home) : 0
        invocation.print(String(decoding: try JSONEncoder.sorted.encode(Answer(dropped: dropped)), as: UTF8.self))
        return 0
    }
}
