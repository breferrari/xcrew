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
    var valuedOptions: Set<String> { Set(Self.mcsKeys.keys).union(["debugger-backend"]) }
    let flags: Set<String> = ["force", "worktree"]
    let usage = [
        "setup [--container NAME] [--test-simulator NAME] [--app-simulator NAME]",
        "      [--app-scheme NAME] [--bundle-id ID] [--ui-scheme NAME] [--test-scheme NAME]",
        "      [--debugger-backend dap|lldb-cli] [--force]",
        "      write .mobilebuildmcp/config.yaml; simulators default to the newest iPhone installed,",
        "      and the test scheme to the shared scheme that runs unit tests",
        "setup --worktree [--force]   in a linked git worktree, write its config from the main checkout's",
    ]

    /// The container setup builds when no option names one: mcs's answer, else the default below.
    static func container(in context: CheckContext) throws -> String {
        try mcsKeys["container"].flatMap { context.machine.value("MCS_RESOLVED_\($0)") } ?? defaultContainer(in: context.project)
    }

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
        if invocation.arguments.has("worktree") { return try await worktree(invocation) }
        func answer(_ option: String) -> String? {
            invocation.arguments[option] ?? Self.mcsKeys[option].flatMap { context.machine.value("MCS_RESOLVED_\($0)") }
        }
        let container = try invocation.arguments["container"] ?? Self.container(in: context)
        let catalog = await SimulatorCatalog.load(using: context.runner, choosingADefault: answer("test-simulator") == nil)
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
        answers.debuggerBackend = invocation.arguments["debugger-backend"]
            ?? (try? String(contentsOf: context.project.mobileBuildMCPConfig, encoding: .utf8)).flatMap(ConfigRenderer.debuggerBackend(in:))
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
        let installed = catalog.iPhoneNames.joined(separator: ", ")
        let missing = [(answers.testSimulator, "test-simulator"), (answers.appSimulator, "app-simulator")].filter { simulatorIDs[$0.0] == nil }
        if !catalog.devices.isEmpty, !missing.isEmpty {
            let runtimes = Data(await context.runner.run("xcrun", "simctl", "list", "runtimes", "--json").stdout.utf8)
            var named: Set<String> = []
            for (name, option) in missing where named.insert(name).inserted {
                let add = SimulatorCatalog.createCommand(for: name, runtimes: runtimes).map { "create it with \($0)" } ?? "add it in Xcode"
                notes.append(installed.isEmpty
                    ? "xcrew: no simulator named \(name) is installed, and no iPhone simulator is: \(add)"
                    : "xcrew: no simulator named \(name) is installed (installed iPhones: \(installed)): \(add), or rerun with --\(option) and one of those")
            }
        }
        let carried = (try? String(contentsOf: context.project.mobileBuildMCPConfig, encoding: .utf8)).map(CarriedDefaults.init) ?? CarriedDefaults()
        let carriedKeys = carried.keys(for: answers.profileNames)
        if !carriedKeys.isEmpty, ConfigWriter.keeping(context.project) != nil {
            notes.append("xcrew: carried \(carriedKeys.joined(separator: ", ")) from the old config into " + (answers.profileNames.isEmpty ? "the session defaults" : "each profile"))
        }
        let outcome = try ConfigWriter.write(answers, to: context.project, simulatorIDs: simulatorIDs, carried: carried, force: invocation.arguments.has("force"))
        Self.report(outcome, in: invocation, written: notes + ["xcrew: wrote .mobilebuildmcp/config.yaml for \(answers.container); restart Claude Code so MobileBuildMCP reads it"])
        if answers.appScheme == nil {
            invocation.print("xcrew: no app profile yet; /xcrew:setup adds the app and UI-test profiles from your schemes")
        }
        await Self.keepOutOfGit(in: invocation)
        return 0
    }

    /// What became of the config: kept as it was, with what `--force` would do, or written, with `written`'s lines.
    static func report(_ outcome: ConfigWriter.Outcome, in invocation: Invocation, written: [String]) {
        switch outcome {
        case .keptEdited:
            invocation.print("xcrew: .mobilebuildmcp/config.yaml was edited after xcrew wrote it; left as is (--force replaces it, keeping a backup)")
        case .keptUnmanaged:
            invocation.print("xcrew: .mobilebuildmcp/config.yaml exists and xcrew didn't write it; left as is (--force replaces it, keeping a backup)")
        case .written(let backup):
            if let backup { invocation.print("xcrew: kept the old config as \(backup.lastPathComponent)") }
            written.forEach(invocation.print)
        }
    }

    /// The config names this Mac's simulators by ID, and DerivedData may live beside it, so it never belongs in the
    /// repository: kept out through the exclude file every worktree of it shares.
    static func keepOutOfGit(in invocation: Invocation) async {
        let context = invocation.context
        if await GitExclusion.exclude(".mobilebuildmcp/", in: context.project, using: context.runner) == .added {
            invocation.print("xcrew: kept .mobilebuildmcp/ out of git (in .git/info/exclude, which isn't committed)")
        }
    }

    /// A linked worktree's config, from its main checkout's: the same profiles and schemes, with an absolute path the
    /// main checkout uses left out, so the worktree's builds don't share its DerivedData.
    func worktree(_ invocation: Invocation) async throws -> Int32 {
        let context = invocation.context
        guard invocation.arguments.values.isEmpty else {
            throw UsageError(description: "setup --worktree takes no option but --force: the profiles are the main checkout's")
        }
        guard let main = await Worktree.mainCheckout(of: context.project, using: context.runner) else {
            throw UsageError(description: "setup --worktree runs in a linked git worktree; this is a main checkout, or not in git")
        }
        guard let yaml = try? String(contentsOf: Project(root: main).mobileBuildMCPConfig, encoding: .utf8) else {
            invocation.print("xcrew: the main checkout (\(main.path)) has no .mobilebuildmcp/config.yaml; xcrew setup there, or plain xcrew setup here, writes one")
            return 1
        }
        let (config, leftOut) = Worktree.config(from: yaml, main: main)
        let outcome = try ConfigWriter.write(config, to: context.project, force: invocation.arguments.has("force"))
        Self.report(outcome, in: invocation, written: ["xcrew: wrote .mobilebuildmcp/config.yaml from the main checkout's (\(main.path)); restart Claude Code so MobileBuildMCP reads it"]
            + leftOut.map { "xcrew: left out \($0.key) \($0.path), which the main checkout uses: this worktree's builds go in a DerivedData of its own" })
        await Self.keepOutOfGit(in: invocation)
        return 0
    }
}
