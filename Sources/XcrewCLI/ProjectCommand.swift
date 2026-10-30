import CryptoKit
import Foundation

import XcrewCore

/// What kind of project this is, as JSON: whether a generator writes it, for the mod's `XcodeWrite` guard, and
/// with `--setup` the container setup would build, for the setup skill, and with `--profiles` the line offering setup, for the mod. The guard runs it on every call, so only
/// the skill pays for the container's search. The mod asks with `--manifest` after each edit to a manifest's name.
struct ProjectCommand: Command {
    let name = "project"
    let flags: Set<String> = ["setup", "profiles", "branch", "xcode"]
    let valuedOptions: Set<String> = ["manifest", "generated", "hash", "profile", "xcuserstate"]
    let usage = [
        "project [--setup] [--profiles [--profile <name>]] [--xcode] [--xcuserstate <file>] [--manifest <file>] [--generated <file>] [--branch] [--hash <file>]   whether a generator writes this project, as JSON; --setup adds the container setup would use, --profiles the line offering setup while MobileBuildMCP has no scheme to build with, and the scheme it builds with once it has, or with --profile that profile's, (default) for the global defaults, --xcode the scheme selected in Xcode when Xcode hosts MobileBuildMCP's server, with the file it's read from and whether MobileBuildMCP follows it, --xcuserstate the scheme selected in <file>, --manifest the command that regenerates the project after an edit to <file>, when the generator reads it, --generated the manifest to edit instead of <file>, when the generator writes it, --branch the real root with the branch or commit checked out, and --hash <file>'s SHA-256, for telling an edit undone",
    ]

    struct Answer: Codable, Equatable {
        let isGenerated: Bool
        var container: String?
        var containerProblem: String?
        /// With `--profiles`: the line offering setup, while MobileBuildMCP has no scheme to build with.
        var setup: String?
        /// With `--profiles`: the scheme MobileBuildMCP builds with when a call names none; with `--profile`, that profile's.
        var scheme: String?
        /// With `--xcode`, when Xcode hosts MobileBuildMCP's server: the profile active at its start, whose scheme it
        /// writes Xcode's selection over, `(default)` for the global defaults; the `xcuserstate` it reads; and whether it
        /// follows that file after its start.
        var activeProfile: String?
        var xcodeState: String?
        var followsXcode: Bool?
        /// With `--xcode`, once MobileBuildMCP's server is found: whether Xcode started it.
        var xcodeHostsServer: Bool?
        /// With `--xcode` or `--xcuserstate <file>`: the scheme selected in Xcode, as MobileBuildMCP reads it.
        var xcodeScheme: String?
        /// The command to run before the next build, when the file `--manifest` names is one the generator reads.
        var generate: String?
        /// The app that command regenerates, as the path of its manifests' folder from the root: empty for the root.
        var app: String?
        /// With `--branch`: the project's real root, and the branch checked out there, or the commit when HEAD is detached.
        var root: String?
        var branch: String?
        var commit: String?
        /// With `--generated`: the manifest to edit instead of the file, when a generator writes it, from the root.
        var manifest: String?
        /// With `--hash`: the file's SHA-256 in hex, for the manifest guard to tell an edit undone; empty when it isn't
        /// there, and none when it's there but can't be read.
        var hash: String?
    }

    /// A file the mod names: absolute, as an edit tool gives it, or from the project's root.
    static func file(_ argument: String, in project: Project) -> URL {
        argument.hasPrefix("/") ? URL(fileURLWithPath: argument) : project.root.appending(path: argument)
    }

    func run(_ invocation: Invocation) async throws -> Int32 {
        let project = invocation.context.project
        let layout = project.layout(.anywhereButHome)
        let nearest = layout.generator
        var answer = Answer(isGenerated: nearest != nil)
        if let manifest = invocation.arguments["manifest"], let nearest {
            let found = layout.command(after: Self.file(manifest, in: project), nearest: nearest)
            (answer.generate, answer.app) = (found?.command, found?.manifests.path)
        }
        if let generated = invocation.arguments["generated"], let nearest {
            if let writer = layout.writer(of: Self.file(generated, in: project), nearest: nearest) {
                (answer.manifest, answer.generate, answer.app) = (writer.manifest, writer.manifests.generateCommand, writer.manifests.path)
            }
        }
        if let file = invocation.arguments["hash"] {
            let url = Self.file(file, in: project)
            // A file that's there but can't be read gives no hash, which leaves an edit standing.
            answer.hash = FileManager.default.fileExists(atPath: url.path) ? (try? Data(contentsOf: url)).map { SHA256.hash(data: $0).hex } : ""
        }
        if invocation.arguments.has("branch") {
            answer.root = project.canonicalRoot
            switch await GitHead.of(project, using: invocation.context.machine.runner) {
            case let .branch(name): answer.branch = name
            case let .commit(sha): answer.commit = sha
            case nil: break
            }
        }
        if invocation.arguments.has("profiles") {
            if let profile = invocation.arguments["profile"] {
                answer.scheme = (try? String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8)).flatMap { ConfigRenderer.schemeToBuild(in: $0, profile: profile) }
            } else if let scheme = project.schemeToBuild {
                answer.scheme = scheme
            } else {
                answer.setup = await SessionBriefing.setupOffer(for: project, using: invocation.context.runner)
            }
        }
        if invocation.arguments.has("xcode"), let read = await XcodeSelection.read(for: project, machine: invocation.context.machine) {
            answer.xcodeHostsServer = read.hostsServer
            if let selection = read.selection {
                (answer.xcodeState, answer.xcodeScheme, answer.followsXcode, answer.activeProfile) = (selection.state.path, selection.scheme, selection.follows, selection.activeProfile)
            }
        }
        if let state = invocation.arguments["xcuserstate"] {
            answer.xcodeScheme = XcodeSelection.scheme(inStateAt: URL(fileURLWithPath: state))
        }
        if invocation.arguments.has("setup") {
            do {
                answer.container = try SetupCommand.container(in: invocation.context)
            } catch {
                answer.containerProblem = String(describing: error)
            }
        }
        invocation.print(String(decoding: try JSONEncoder.sorted.encode(answer), as: UTF8.self))
        return 0
    }
}
