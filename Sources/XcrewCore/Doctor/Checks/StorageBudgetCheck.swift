import Foundation

/// This project's MobileBuildMCP storage, its live checkouts' workspaces together, against a budget, with the dry run that
/// lists what `purge` would delete; it never deletes. It asks for each checkout's workspace alone: sizing every workspace
/// on a Mac took 21.7 s where one project's took 0.8 s (a field report, about 190 GB). `xcrew space` gives the whole Mac.
/// The report walks the workspace's files, so it runs only in the full doctor.
struct StorageBudgetCheck: Check {
    let id = "mobilebuildmcp/storage"
    let title = "This project's MobileBuildMCP storage is within its budget"
    let walksFiles = true

    /// The budget in GB unless `XCREW_STORAGE_BUDGET_GB` sets another: a choice, above what a single large modular app's
    /// DerivedData takes, so that alone isn't named.
    static let budgetGB = 40.0
    static let budgetVariable = "XCREW_STORAGE_BUDGET_GB"
    /// The largest budget taken, beyond any disk.
    static let largestGB = 1_000_000.0

    func run(_ context: CheckContext) async -> CheckResult {
        let machine = context.machine
        guard machine.hasMobileBuildMCP else { return .skip("MobileBuildMCP isn't installed") }
        let checkouts = await ProjectWorkspaces.live(of: context.project, using: machine.runner)
        let reports = await withTaskGroup(of: (ProjectWorkspaces.Checkout, StorageReport?).self) { group in
            for checkout in checkouts { group.addTask { (checkout, await StorageReport.read(.workspace(checkout.key), using: machine.runner)) } }
            return await group.reduce(into: []) { $0.append($1) }
        }
        guard reports.contains(where: { $0.1 != nil }) else { return .skip("`mobilebuildmcp purge --report` didn't answer") }
        let live = reports.flatMap { checkout, report in (report?.workspaces ?? []).filter { $0.key == checkout.key }.map { (workspace: $0, checkout: checkout) } }
            .sorted { $0.workspace.bytes > $1.workspace.bytes }
        let budget = Self.budget(machine)
        let total = live.map(\.workspace.bytes).reduce(0, +)
        if let past = Self.pastBudget(live, total: total, budget: budget) { return .warn(past) }
        return .pass("this project's MobileBuildMCP workspaces take \(SpaceReport.size(total)), within its budget of \(Self.said(budget))")
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

    static func pastBudget(_ live: [(workspace: StorageReport.Workspace, checkout: ProjectWorkspaces.Checkout)], total: Int, budget: Double) -> String? {
        guard Double(total) > budget * 1e9, let largest = live.first else { return nil }
        let name = URL(fileURLWithPath: largest.checkout.root).lastPathComponent
        let dryRun = Space.purge(largest.workspace).map { ": `\($0)` lists what it would delete" } ?? ""
        return "this project's MobileBuildMCP workspaces take \(SpaceReport.size(total)), past its budget of \(said(budget)); the largest, \(name) (\(largest.checkout.root)), takes \(SpaceReport.size(largest.workspace.bytes))\(dryRun)"
    }
}
