import Foundation

/// This project's MobileBuildMCP storage, its live checkouts' workspaces together, against a budget; and on this Mac, the
/// workspaces whose project folder is gone. Each with the dry run that lists what `purge` would free; it never deletes,
/// and never names `--scope all`. The report walks every file, so it runs only in the full doctor.
struct StorageBudgetCheck: Check {
    let id = "mobilebuildmcp/storage"
    let title = "This project's MobileBuildMCP storage is within its budget"
    let walksFiles = true

    /// The budget in GB, unless `XCREW_STORAGE_BUDGET_GB` sets another: a large modular app's DerivedData alone can pass
    /// 20 GB, which is no fault.
    static let budgetGB = 40.0
    static let budgetVariable = "XCREW_STORAGE_BUDGET_GB"

    func run(_ context: CheckContext) async -> CheckResult {
        let machine = context.machine
        guard machine.hasMobileBuildMCP else { return .skip("MobileBuildMCP isn't installed") }
        guard let report = await StorageReport.read(.all, using: machine.runner) else { return .skip("`mobilebuildmcp purge --report` didn't answer") }
        let live = await ProjectWorkspaces.live(of: context.project, using: machine.runner)
        let origins = await ProjectWorkspaces.origins(of: report, live: live, home: machine.home)
        let budget = machine.value(Self.budgetVariable).flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil } ?? Self.budgetGB
        let named = "\(budget.rounded() == budget ? String(Int(budget)) : String(budget)) GB (\(Self.budgetVariable) sets another)"
        let ours = report.workspaces.compactMap { workspace -> (workspace: StorageReport.Workspace, root: String)? in
            guard case let .live(checkout)? = origins[workspace.key] else { return nil }
            return (workspace, checkout.root)
        }
        let total = ours.map(\.workspace.bytes).reduce(0, +)
        var found: [String] = []
        if Double(total) > budget * 1e9, let largest = ours.max(by: { $0.workspace.bytes < $1.workspace.bytes }) {
            let name = URL(fileURLWithPath: largest.root).lastPathComponent
            let dryRun = Space.purge(largest.workspace).map { ": `\($0)` lists what it would free" } ?? ""
            found.append("this project's MobileBuildMCP workspaces take \(SpaceReport.size(total)), past its budget of \(named); the largest, \(name) (\(largest.root)), takes \(SpaceReport.size(largest.workspace.bytes))\(dryRun)")
        }
        let gone = report.workspaces.filter { if case .gone? = origins[$0.key] { true } else { false } }
        if !gone.isEmpty {
            let one = gone.count == 1
            let dryRuns = gone.compactMap(Space.purge).map { "`\($0)`" }.joined(separator: ", ")
            let listed = dryRuns.isEmpty ? "" : ": \(dryRuns) list\(gone.count == 1 ? "s" : "") \(one ? "it" : "them")"
            found.append("on this Mac, \(gone.count) \(one ? "workspace" : "workspaces") whose project folder is gone \(one ? "takes" : "take") \(SpaceReport.size(gone.map(\.bytes).reduce(0, +)))\(listed)")
        }
        guard found.isEmpty else { return .warn(found.joined(separator: "; ")) }
        return .pass("this project's MobileBuildMCP workspaces take \(SpaceReport.size(total)), within its budget of \(named)")
    }
}
