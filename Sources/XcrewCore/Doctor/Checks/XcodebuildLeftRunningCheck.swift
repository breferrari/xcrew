import Foundation

/// An xcodebuild still building the project when no call is waiting on it holds the project's build folder, and the next
/// build into it fails with `database is locked`. MobileBuildMCP starts xcodebuild as a child of its server and doesn't
/// stop it when a call is stopped (docs/findings.md, *Builds that fail because of the Mac*); when the session ends, it
/// goes on under launchd. Under a live server a stopped call's xcodebuild and a backgrounded call's look the same, so
/// that one is said both ways and stays off the prompt. One started from a terminal is the person's.
struct XcodebuildLeftRunningCheck: Check {
    let id = "mobilebuildmcp/no-xcodebuild-left"
    let title = "No xcodebuild left running for this project"

    func run(_ context: CheckContext) async -> CheckResult {
        let list = await ProcessList.load(using: context.runner)
        guard !list.processes.isEmpty else { return .skip("couldn't list the processes") }
        let builds = list.processes.filter(\.isXcodebuild)
        let folders = await ProcessList.folders(of: builds, using: context.runner)
        let root = ProjectLayout.canonical(context.project.root)
        let projects = builds.filter { build in
            folders[build.id] == root || [context.project.root.path, root].contains { build.command.contains($0 + "/") }
        }
        // The process that started it, past an `xcrun` that ran it: launchd's pid 1 once its session ended.
        func starter(of build: ProcessList.Process) -> (id: Int32, above: [ProcessList.Process]) {
            let above = list.ancestors(of: build.id)
            let first = above.first { $0.program != "xcrun" }
            return (first?.id ?? above.last?.parent ?? build.parent, above)
        }
        if let left = projects.first(where: { starter(of: $0).id == 1 }) {
            return .warn("an xcodebuild still builds this project after its Claude Code session ended, holding its build folder: \(left.described). Stopping it frees the folder: kill \(left.id)")
        }
        if let served = projects.first(where: { starter(of: $0).above.contains(where: ProcessList.isMobileBuildMCPServer) }) {
            return .warn("an xcodebuild MobileBuildMCP started still builds this project, holding its build folder: \(served.described). A call stopped partway leaves its xcodebuild running; a call moved to the background is still building. Stopping it frees the folder: kill \(served.id)").offThePrompt()
        }
        return .pass("no xcodebuild left running for this project")
    }
}
