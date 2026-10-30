import Foundation

/// An xcodebuild still building the project when no call is waiting on it holds the project's build folder, and the next
/// build into it fails with `database is locked`. MobileBuildMCP starts xcodebuild as a child of its server and doesn't
/// stop it when a call is stopped (docs/findings.md, *Builds that fail because of the Mac*); once the session ends it goes
/// on under launchd, or under a server left running without its Claude Code. Under a live session a stopped call's
/// xcodebuild and a backgrounded call's look the same, so that one is said both ways and stays off the prompt. One a
/// terminal, or Claude's own shell, started is someone's still. A worktree or another checkout inside the project is not
/// the project.
struct XcodebuildLeftRunningCheck: Check {
    let id = "mobilebuildmcp/no-xcodebuild-left"
    let title = "No xcodebuild left running for this project"

    func run(_ context: CheckContext) async -> CheckResult {
        let list = await context.processes.value()
        guard !list.processes.isEmpty else { return .skip("couldn't list the processes") }
        let builds = list.processes.filter { $0.isXcodebuild && !$0.asksOnly }
        guard !builds.isEmpty else { return .pass(Self.none) }
        let folders = await ProcessList.folders(of: builds, using: context.runner)
        guard !folders.isEmpty else { return .skip("couldn't read the xcodebuilds' folders") }
        let root = context.project.canonicalRoot
        let projects = builds.filter { build in
            let folder = folders[build.id]
            let from = build.buildsFrom.map { URL(fileURLWithPath: $0, relativeTo: folder.map { URL(fileURLWithPath: $0, isDirectory: true) }) }
            return ([folder] + [from.map { ProjectLayout.canonical($0.deletingLastPathComponent()) }]).contains { $0.map { Self.path($0, isIn: root) } == true }
        }
        let classified = projects.map { build in
            let above = list.ancestors(of: build.id)
            let served = above.contains(where: ProcessList.isMobileBuildMCPServer)
            let live = above.contains { $0.program == "claude" }
            return (build, ended: !live && (served || list.starter(of: build.id) == 1), served: served && live)
        }
        if let left = classified.first(where: \.ended)?.0 {
            return .warn(Self.building(left, "an xcodebuild whose starter has exited", "A call stopped partway leaves one once its session ends. "))
        }
        if let served = classified.first(where: \.served)?.0 {
            return .warn(Self.building(served, "an xcodebuild MobileBuildMCP started", "A call stopped partway leaves its xcodebuild running; a call moved to the background is still building. ")).offThePrompt()
        }
        return .pass(Self.none)
    }

    static let none = "no xcodebuild left running for this project"

    /// `<who> still builds this project, holding its build folder: <pid, destination, age>. <why>Stopping it…: kill <pid>`
    static func building(_ build: ProcessList.Process, _ who: String, _ why: String) -> String {
        "\(who) still builds this project, holding its build folder: \(build.described). \(why)Stopping it frees the folder: kill \(build.id)"
    }

    /// Whether `path` is `root` or in it, and not in a checkout of its own between them, such as a worktree.
    static func path(_ path: String, isIn root: String) -> Bool {
        guard path == root || path.hasPrefix(root + "/") else { return false }
        var folder = URL(fileURLWithPath: path)
        while folder.path.count > root.count {
            if FileManager.default.fileExists(atPath: folder.appending(path: ".git").path) { return false }
            folder.deleteLastPathComponent()
        }
        return true
    }
}
