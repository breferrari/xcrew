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
        "test-scheme": "TEST_SCHEME",
    ]

    let name = "setup"
    var valuedOptions: Set<String> { Set(Self.mcsKeys.keys) }
    let flags: Set<String> = ["force"]
    let usage = [
        "setup [--container NAME] [--test-simulator NAME] [--app-simulator NAME]",
        "      [--app-scheme NAME] [--bundle-id ID] [--ui-scheme NAME] [--test-scheme NAME] [--force]",
        "      write .mobilebuildmcp/config.yaml; simulators default to the newest iPhone installed,",
        "      and the test scheme to the shared scheme that runs unit tests",
    ]

    /// The container to build when none is named: the nearest, and in a generated project the one beside its manifests,
    /// since a module's own project isn't the app. Below the root, two folders' containers equally near are a question.
    static func defaultContainer(in project: Project) throws -> String {
        let layout = project.layout(.anywhereButHome)
        let containers = layout.containers
        let manifests = layout.generator
        let candidates = manifests.map { manifests in containers.filter { ($0 as NSString).deletingLastPathComponent == manifests.path } } ?? containers
        guard let nearest = candidates.first else {
            if let manifests, !containers.isEmpty {
                throw UsageError(description: "no workspace beside the manifests in \(manifests.path.isEmpty ? "the project root" : manifests.path) yet: generate it first, or pass --container")
            }
            throw UsageError(description: "no .xcworkspace or .xcodeproj in \(project.root.path) or a folder or two below it: generate it first, or pass --container")
        }
        // A workspace and the project beside it are one choice; containers come workspaces first.
        let folders = candidates.reduce(into: [String: String]()) { $0[($1 as NSString).deletingLastPathComponent] = $0[($1 as NSString).deletingLastPathComponent] ?? $1 }
        if folders.count > 1, nearest.contains("/") {
            throw UsageError(description: "several projects a folder or two down (\(folders.values.sorted().joined(separator: ", "))): pass --container")
        }
        return nearest
    }

    func run(_ invocation: Invocation) async throws -> Int32 {
        let context = invocation.context
        func answer(_ option: String) -> String? {
            invocation.arguments[option] ?? Self.mcsKeys[option].flatMap { context.machine.value("MCS_RESOLVED_\($0)") }
        }
        let container = try answer("container") ?? Self.defaultContainer(in: context.project)
        let catalog = await SimulatorCatalog.load(using: context.runner)
        guard let testSimulator = answer("test-simulator") ?? catalog.defaultIPhone else {
            throw UsageError(description: "no iPhone simulator installed: add one in Xcode, or pass --test-simulator")
        }
        var answers = ProfileAnswers(
            container: container,
            testSimulator: testSimulator,
            appSimulator: answer("app-simulator"),
            appScheme: answer("app-scheme"),
            bundleID: answer("bundle-id"),
            uiTestScheme: answer("ui-scheme"),
            testScheme: answer("test-scheme")
        )
        // Said only once the config is written, since a kept config ignores them.
        var notes: [String] = []
        if answers.testScheme == nil {
            let ask = "pass --test-scheme <name> to add the unit profile"
            switch TestSchemes.choose(in: context.project.root.appending(path: container), preferring: answers.appScheme) {
            case .scheme(let scheme):
                answers.testScheme = scheme
                notes.append("xcrew: unit tests run with the \(scheme) scheme (--test-scheme <name> picks another)")
            case .several(let schemes):
                notes.append("xcrew: several schemes run unit tests (\(schemes.joined(separator: ", "))): \(ask)")
            case .unknown(let schemes):
                notes.append("xcrew: couldn't tell whether these schemes run unit tests (\(schemes.joined(separator: ", "))): \(ask)")
            case .none:
                break
            }
        }
        let simulatorIDs = [answers.testSimulator, answers.appSimulator].reduce(into: [String: String]()) { ids, name in
            ids[name] = catalog.udid(of: name)
        }
        switch try ConfigWriter.write(answers, to: context.project, simulatorIDs: simulatorIDs, force: invocation.arguments.has("force")) {
        case .keptEdited:
            invocation.print("xcrew: .mobilebuildmcp/config.yaml was edited after xcrew wrote it; left as is (--force replaces it, keeping a backup)")
        case .keptUnmanaged:
            invocation.print("xcrew: .mobilebuildmcp/config.yaml exists and xcrew didn't write it; left as is (--force replaces it, keeping a backup)")
        case .written(let backup):
            if let backup { invocation.print("xcrew: kept the old config as \(backup.lastPathComponent)") }
            notes.forEach(invocation.print)
            invocation.print("xcrew: wrote .mobilebuildmcp/config.yaml for \(answers.container); restart Claude Code so MobileBuildMCP reads it")
        }
        if answers.appScheme == nil {
            invocation.print("xcrew: no app profile yet; /xcrew:setup adds the app and UI-test profiles from your schemes")
        }
        // The config holds this Mac's absolute paths, so it never belongs in the repository.
        if await GitExclusion.exclude(".mobilebuildmcp/", in: context.project, using: context.runner) == .added {
            invocation.print("xcrew: kept .mobilebuildmcp/ out of git (in .git/info/exclude, which isn't committed)")
        }
        return 0
    }
}
