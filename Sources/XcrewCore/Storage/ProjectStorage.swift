import Foundation

/// This project's MobileBuildMCP storage, its live checkouts' workspaces together: the first line of `xcrew space`'s
/// MobileBuildMCP part, from the report it reads. It walks every file, so it's said only when asked. It says what takes
/// the space and measures it against nothing.
enum ProjectStorage {
    /// The total, in both units, the class that takes the most, and whether a build is writing to a workspace as it's read,
    /// which makes it larger than it stays.
    static func line(_ live: [(workspace: StorageReport.Workspace, checkout: ProjectWorkspaces.Checkout)], machine: Machine, processes: ProcessList) -> String {
        let total = live.map(\.workspace.bytes).reduce(0, +)
        let building = live.contains { Space.isBuilding(into: $0.workspace, processes: processes, home: machine.home) } ? "; a build is writing to them now, so they take more than they will after it" : ""
        return "this project's MobileBuildMCP workspaces take \(SpaceReport.size(total)) (\(SpaceReport.binarySize(total)) as `du -h` counts)\(largestClass(live.map(\.workspace)))\(building)"
    }

    /// What MobileBuildMCP calls each class, as a person reads it.
    static let classNames = ["derivedData": "DerivedData", "testProducts": "test products", "resultBundles": "result bundles", "logs": "logs", "stateTransients": "state transients", "locks": "locks"]

    /// `; DerivedData takes the most, 77.9 MB`, the class that takes the most across the workspaces; nothing when no class
    /// holds anything.
    static func largestClass(_ workspaces: [StorageReport.Workspace]) -> String {
        let sums = workspaces.flatMap(\.classes).reduce(into: [String: Int]()) { $0[$1.key, default: 0] += $1.value.bytes }
        guard let largest = sums.filter({ $0.value > 0 }).max(by: { ($0.value, $1.key) < ($1.value, $0.key) }) else { return "" }
        return "; \(classNames[largest.key] ?? largest.key) takes the most, \(SpaceReport.size(largest.value))"
    }
}
