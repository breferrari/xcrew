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
        let processes = await context.processes.value()
        let building = live.contains { Space.isBuilding(into: $0.workspace, processes: processes, home: machine.home) } ? "; a build is writing to them now, so they take more than they will after it" : ""
        let taken = "this project's MobileBuildMCP workspaces take \(SpaceReport.size(total)) (\(SpaceReport.binarySize(total)) as `du -h` counts)"
        if Double(total) > budget * 1e9 { return .warn("\(taken), past its budget of \(Self.said(budget))\(Self.largestClass(live.map(\.workspace)))\(building)") }
        return .pass("\(taken), within its budget of \(Self.said(budget))\(building)")
    }

    /// What MobileBuildMCP calls each class, as a person reads it.
    static let classNames = ["derivedData": "DerivedData", "testProducts": "test products", "resultBundles": "result bundles", "logs": "logs", "stateTransients": "state transients", "locks": "locks"]

    /// `; DerivedData takes the most, 77.9 MB: …`, the class that takes the most across the workspaces, and where the rest
    /// is said; nothing when no class holds anything.
    static func largestClass(_ workspaces: [StorageReport.Workspace]) -> String {
        let sums = workspaces.flatMap(\.classes).reduce(into: [String: Int]()) { $0[$1.key, default: 0] += $1.value.bytes }
        guard let largest = sums.filter({ $0.value > 0 }).max(by: { ($0.value, $1.key) < ($1.value, $0.key) }) else { return "" }
        return "; \(classNames[largest.key] ?? largest.key) takes the most, \(SpaceReport.size(largest.value)): `xcrew space` names what each part would reclaim"
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
}
