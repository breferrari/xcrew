import Foundation

/// No simulator `setup --worktree` recorded making is left behind: its worktree removed, or its runtime gone, where setup
/// would make another. Only the record is judged, never a name, which another clone of a folder of the same name shares.
/// Names each with the command that removes it; deletes nothing. Said by `xcrew space`, which shows it as a part of its
/// own; a skip shows none.
enum WorktreeLeftovers {
    static func run(_ context: CheckContext) async -> CheckResult {
        guard let file = await WorktreeSimulatorRecord.file(for: context.project.root, using: context.runner) else { return .skip("not in git") }
        let record = WorktreeSimulatorRecord.read(file)
        guard !record.entries.isEmpty else { return .skip("setup --worktree has recorded none") }
        let listed = await context.runner.run("xcrun", "simctl", "list", "devices", "--json")
        let git = await context.runner.run("git", "-C", context.project.root.path, "worktree", "list", "--porcelain")
        guard listed.succeeded, git.succeeded else { return .skip("simctl or git didn't answer") }
        let devices = SimulatorCatalog(json: Data(listed.stdout.utf8), includingUnavailable: true).devices
        let live = Set(Worktree.checkouts(listed: git.stdout).filter { !$0.isPrunable }.map { ProjectLayout.canonicalPath($0.top) })
        let ours = record.entries.compactMap { entry in devices.first { $0.udid == entry.udid }.map { (device: $0, entry: entry) } }
        let left = ours.compactMap { device, entry -> (device: SimulatorCatalog.Device, why: String)? in
            if !live.contains(ProjectLayout.canonicalPath(entry.worktree)) { return (device, "its worktree is gone") }
            return device.isAvailable ? nil : (device, "its runtime is gone")
        }
        guard !ours.isEmpty else { return .pass("none of those made for this repository's worktrees is left") }
        guard !left.isEmpty else { return .pass("\(ours.count) made for this repository's worktrees, each still there") }
        let named = left.map { "`\($0.device.name)` (\($0.why))" }.joined(separator: ", ")
        return .warn(Self.leftovers(named: named, udids: left.compactMap(\.device.udid)))
    }

    /// What's said of the simulators `named`: deleting them loses the apps on them and their data, the person's call, said
    /// before the command, which ends the text.
    static func leftovers(named: String, udids: [String]) -> String {
        let them = udids.count == 1 ? "it" : "them"
        return "\(named). Deleting \(them) \(SimulatorDelete.loses(them)): `xcrun simctl delete \(udids.joined(separator: " "))`"
    }
}
