import Foundation

/// This project's MobileBuildMCP storage, its live checkouts' workspaces together, against a budget: the first line of
/// `xcrew space`'s MobileBuildMCP part, from the report it reads. It walks every file, so it's said only when asked.
enum StorageBudget {
    /// The budget in GB unless `XCREW_STORAGE_BUDGET_GB` sets another: a choice, above what a single large modular app's
    /// DerivedData takes, so that alone isn't named.
    static let budgetGB = 40.0
    static let budgetVariable = "XCREW_STORAGE_BUDGET_GB"
    /// The largest budget taken, beyond any disk.
    static let largestGB = 1_000_000.0

    /// The total, in both units, against the budget; past it, the class that takes the most; and whether a build is writing
    /// to a workspace as it's read, which makes it larger than it stays.
    static func line(_ live: [(workspace: StorageReport.Workspace, checkout: ProjectWorkspaces.Checkout)], machine: Machine, processes: ProcessList) -> String {
        let budget = budget(machine)
        let total = live.map(\.workspace.bytes).reduce(0, +)
        let building = live.contains { Space.isBuilding(into: $0.workspace, processes: processes, home: machine.home) } ? "; a build is writing to them now, so they take more than they will after it" : ""
        let taken = "this project's MobileBuildMCP workspaces take \(SpaceReport.size(total)) (\(SpaceReport.binarySize(total)) as `du -h` counts)"
        if Double(total) > budget * 1e9 { return "\(taken), past its budget of \(said(budget))\(largestClass(live.map(\.workspace)))\(building)" }
        return "\(taken), within its budget of \(said(budget))\(building)"
    }

    /// `XCREW_STORAGE_BUDGET_GB` when it's a finite number of GB above nothing and at most `largestGB`, else the default.
    static func budget(_ machine: Machine) -> Double {
        guard let set = machine.value(budgetVariable).flatMap(Double.init), set.isFinite, set > 0, set <= largestGB else { return budgetGB }
        return set
    }

    /// `40 GB (XCREW_STORAGE_BUDGET_GB sets another)`, for a budget `budget(_:)` gave, which a whole `Int` holds.
    static func said(_ budget: Double) -> String {
        "\(budget.rounded() == budget ? String(Int(budget)) : String(budget)) GB (\(budgetVariable) sets another)"
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
