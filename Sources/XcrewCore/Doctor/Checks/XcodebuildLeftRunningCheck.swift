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
        let list = await context.processes.value()
        guard !list.processes.isEmpty else { return .skip("couldn't list the processes") }
        let builds = list.processes.filter(\.isXcodebuild)
        let folders = await ProcessList.folders(of: builds, using: context.runner)
        let root = context.project.canonicalRoot
        let projects = builds.filter { build in
            folders[build.id] == root || [context.project.root.path, root].contains { build.command.contains($0 + "/") }
        }
        // The process that started it, past an `xcrun` that ran it: launchd's pid 1 once its session ended.
        func starter(of build: ProcessList.Process) -> Int32 {
            let above = list.ancestors(of: build.id)
            return above.first { $0.program != "xcrun" }?.id ?? above.last?.parent ?? build.parent
        }
        if let left = projects.first(where: { starter(of: $0) == 1 }) {
            return .warn(Self.building(left, "an xcodebuild still builds this project after its Claude Code session ended"))
        }
        if let served = projects.first(where: { list.ancestors(of: $0.id).contains(where: ProcessList.isMobileBuildMCPServer) }) {
            return .warn(Self.building(served, "an xcodebuild MobileBuildMCP started still builds this project", "A call stopped partway leaves its xcodebuild running; a call moved to the background is still building. ")).offThePrompt()
        }
        return .pass("no xcodebuild left running for this project")
    }

    /// `<who> still builds this project, holding its build folder: <pid, destination, age>. <why>Stopping it…: kill <pid>`
    static func building(_ build: ProcessList.Process, _ who: String, _ why: String = "") -> String {
        "\(who), holding its build folder: \(build.described). \(why)Stopping it frees the folder: kill \(build.id)"
    }
}
