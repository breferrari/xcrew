import Foundation

import XcrewCore

/// Writes `.mobilebuildmcp/config.yaml`. Each option falls back to mcs's `MCS_RESOLVED_<KEY>`,
/// so mcs's configure step is `xcrew setup` with no arguments.
struct SetupCommand: Command {
    /// Option name → the mcs prompt key that answers it.
    public static let mcsKeys: [String: String] = [
        "container": "PROJECT",
        "test-simulator": "TEST_SIMULATOR",
        "app-simulator": "APP_SIMULATOR",
        "app-scheme": "APP_SCHEME",
        "bundle-id": "APP_BUNDLE_ID",
        "ui-scheme": "UI_TEST_SCHEME",
    ]

    let name = "setup"
    var valuedOptions: Set<String> { Set(Self.mcsKeys.keys) }
    let flags: Set<String> = ["force"]
    let usage = [
        "setup [--container NAME] [--test-simulator NAME] [--app-simulator NAME]",
        "      [--app-scheme NAME] [--bundle-id ID] [--ui-scheme NAME] [--force]",
        "      write .mobilebuildmcp/config.yaml; simulators default to the newest iPhone installed",
    ]

    func run(_ invocation: Invocation) async throws -> Int32 {
        let context = invocation.context
        func answer(_ option: String) -> String? {
            invocation.arguments[option] ?? Self.mcsKeys[option].flatMap { context.machine.value("MCS_RESOLVED_\($0)") }
        }
        guard let container = answer("container") ?? context.project.xcodeContainers.first else {
            throw UsageError(description: "no .xcworkspace or .xcodeproj in \(context.project.root.path): generate it first, or pass --container")
        }
        var testSimulator = answer("test-simulator")
        if testSimulator == nil { testSimulator = await SimulatorCatalog.load(using: context.runner).defaultIPhone }
        guard let testSimulator else {
            throw UsageError(description: "no iPhone simulator installed: add one in Xcode, or pass --test-simulator")
        }
        let answers = ProfileAnswers(
            container: container,
            testSimulator: testSimulator,
            appSimulator: answer("app-simulator"),
            appScheme: answer("app-scheme"),
            bundleID: answer("bundle-id"),
            uiTestScheme: answer("ui-scheme")
        )
        switch try ConfigWriter.write(answers, to: context.project, force: invocation.arguments.has("force")) {
        case .keptEdited:
            invocation.print("xcrew: .mobilebuildmcp/config.yaml was edited after xcrew wrote it; left as is (--force replaces it, keeping a backup)")
        case .keptUnmanaged:
            invocation.print("xcrew: .mobilebuildmcp/config.yaml exists and xcrew didn't write it; left as is (--force replaces it, keeping a backup)")
        case .written(let backup):
            if let backup { invocation.print("xcrew: kept the old config as \(backup.lastPathComponent)") }
            invocation.print("xcrew: wrote .mobilebuildmcp/config.yaml for \(answers.container) (unit tests on \(answers.testSimulator)); restart Claude Code so MobileBuildMCP reads it")
        }
        if answers.appScheme == nil {
            invocation.print("xcrew: only the unit-test profile so far; /xcrew:setup adds the app and UI-test profiles from your schemes")
        }
        // The config holds this Mac's absolute paths, so it never belongs in the repository.
        if await GitExclusion.exclude(".mobilebuildmcp/", in: context.project, using: context.runner) == .added {
            invocation.print("xcrew: kept .mobilebuildmcp/ out of git (in .git/info/exclude, which isn't committed)")
        }
        return 0
    }
}
