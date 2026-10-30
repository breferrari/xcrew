import Foundation

import XcrewCore

/// What kind of project this is, as JSON: whether a generator writes it, for the mod's `XcodeWrite` guard, and
/// with `--setup` the container setup would build, for the setup skill, and with `--profiles` the line offering setup, for the mod. The guard runs it on every call, so only
/// the skill pays for the container's search. The mod asks with `--manifest` after each edit to a manifest's name.
struct ProjectCommand: Command {
    let name = "project"
    let flags: Set<String> = ["setup", "profiles", "branch"]
    let valuedOptions: Set<String> = ["manifest", "generated"]
    let usage = [
        "project [--setup] [--profiles] [--manifest <file>] [--generated <file>] [--branch]   whether a generator writes this project, as JSON; --setup adds the container setup would use, --profiles the line offering setup while MobileBuildMCP has no scheme to build with, --manifest the command that regenerates the project after an edit to <file>, when the generator reads it, --generated the manifest to edit instead of <file>, when the generator writes it, and --branch the real root with the branch or commit checked out",
    ]

    struct Answer: Codable, Equatable {
        let isGenerated: Bool
        var container: String?
        var containerProblem: String?
        /// With `--profiles`: the line offering setup, while MobileBuildMCP has no scheme to build with.
        var setup: String?
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
        if invocation.arguments.has("branch") {
            answer.root = project.canonicalRoot
            switch await GitHead.of(project, using: invocation.context.machine.runner) {
            case let .branch(name): answer.branch = name
            case let .commit(sha): answer.commit = sha
            case nil: break
            }
        }
        if invocation.arguments.has("profiles"), !project.hasSchemeToBuild {
            answer.setup = await SessionBriefing.setupOffer(for: project, using: invocation.context.runner)
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
