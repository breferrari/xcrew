import Foundation

/// The simulators booted now, against this Mac's memory, by the two measures of one settled simulator that disagree
/// (docs/findings.md, *Worktree sessions*). Advice, so it stays off the prompt.
struct SimulatorMemoryCheck: Check {
    let id = "simulators/memory"
    let title = "Booted simulators fit this Mac's memory"

    /// One settled, idle simulator's memory, in MB, measured once on one Mac: what `vm_stat` showed more in use after its
    /// boot, and what `footprint` summed over its processes.
    static let settledMB = (vmStat: 6_644, footprint: 11_247)

    /// Past this share of the Mac's memory by the lower measure, the booted simulators are named.
    static let warnAt = 0.75

    func run(_ context: CheckContext) async -> CheckResult {
        guard let booted = await SimulatorCatalog.bootedIfServiceRuns(using: context.runner, timeout: .seconds(10)) else {
            return .skip("simctl didn't say which simulators are booted")
        }
        guard !booted.isEmpty else { return .pass("none booted") }
        let sysctl = await context.runner.run("sysctl", "-n", "hw.memsize")
        guard sysctl.succeeded, let bytes = Double(sysctl.stdout.trimmingCharacters(in: .whitespacesAndNewlines)), bytes > 0 else {
            return .skip("this Mac's memory couldn't be read")
        }
        let low = Double(Self.settledMB.vmStat * booted.count) / 1024
        let high = Double(Self.settledMB.footprint * booted.count) / 1024
        let memory = bytes / Double(1 << 30)
        let measured = "about \(Int(low.rounded()))–\(Int(high.rounded())) GB by two measures that disagree (measured on one Mac), of \(Int(memory.rounded())) GB"
        guard low >= memory * Self.warnAt else { return .pass("\(booted.count) booted: \(measured)") }
        let names = booted.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return .warn("\(booted.count) booted simulators take \(measured); `xcrun simctl shutdown <name>` shuts one down: \(names.joined(separator: ", "))").offThePrompt()
    }
}
