import Foundation

/// This project's MobileBuildMCP storage, its live checkouts' workspaces together, against a budget; and on this Mac, the
/// workspaces whose project folder is gone. Each with the dry run that lists what `purge` would delete; it never deletes,
/// and never names `--scope all`. The report walks every file, so it runs only in the full doctor.
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
        async let live = ProjectWorkspaces.live(of: context.project, using: machine.runner)
        guard let report = await StorageReport.read(.all, using: machine.runner) else { return .skip("`mobilebuildmcp purge --report` didn't answer") }
        let grouped = ProjectWorkspaces.grouped(report, origins: await ProjectWorkspaces.origins(of: report, live: await live, home: machine.home))
        let budget = Self.budget(machine)
        let total = grouped.live.map(\.workspace.bytes).reduce(0, +)
        let found = [Self.pastBudget(grouped.live, total: total, budget: budget), Self.gone(grouped.gone)].compactMap(\.self)
        guard found.isEmpty else { return .warn(found.joined(separator: "; ")) }
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

    /// The Mac's, not this project's: a confirmed-gone root is no one's.
    static func gone(_ gone: [(workspace: StorageReport.Workspace, root: String)]) -> String? {
        guard !gone.isEmpty else { return nil }
        let dryRuns = gone.compactMap { Space.purge($0.workspace) }.map { "`\($0)`" }
        let listed = switch dryRuns.count {
        case 0: ""
        case 1: ": \(dryRuns[0]) lists what it would delete"
        default: ": \(dryRuns.joined(separator: ", ")) list what they would delete"
        }
        let verb = gone.count == 1 ? "takes" : "take"
        let size = SpaceReport.size(gone.map(\.workspace.bytes).reduce(0, +))
        return "on this Mac, \(Space.counted(gone.count, "workspace")) whose project folder is gone \(verb) \(size) (\(gone.map(\.root).joined(separator: ", ")))\(listed)"
    }
}
