import Foundation

/// Every simulator the profiles name exists, on any installed runtime.
struct SimulatorsCheck: Check {
    let id = "mobilebuildmcp/simulators"
    let title = "Configured simulators exist"

    func run(_ context: CheckContext) async -> CheckResult {
        guard let yaml = try? String(contentsOf: context.project.mobileBuildMCPConfig, encoding: .utf8) else {
            return .skip(context.project.layout(.anywhereButHome).isApplePlatform ? "no config" : "not an Apple project")
        }
        let wanted = ConfigRenderer.simulatorNames(in: yaml)
        guard !wanted.isEmpty else { return .skip("no simulators named") }
        let installed = await SimulatorCatalog.load(using: context.runner).names
        let missing = wanted.filter { !installed.contains($0) }
        guard missing.isEmpty else {
            return .warn("missing: \(missing.joined(separator: ", ")) (xcrun simctl create \"<name>\" <device-type> <runtime>, or xcrew setup to pick installed ones)")
        }
        return .pass(wanted.joined(separator: ", "))
    }
}
