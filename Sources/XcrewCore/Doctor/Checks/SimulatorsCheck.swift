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
        let catalog = await SimulatorCatalog.load(using: context.runner, displaysOf: Set(wanted))
        let missing = wanted.filter { !catalog.names.contains($0) }
        guard missing.isEmpty else {
            let runtimes = Data(await context.runner.run("xcrun", "simctl", "list", "runtimes", "--json").stdout.utf8)
            let installed = catalog.iPhoneNames.isEmpty ? "none" : catalog.iPhoneNames.joined(separator: ", ")
            let unitSimulator = CarriedDefaults(yaml).simulatorName(of: "unit")
            return .warn(missing.map { name in
                let replace = "use an installed one with xcrew setup --\(name == unitSimulator ? "test-simulator" : "app-simulator") <name> (installed iPhones: \(installed))"
                return SimulatorCatalog.createCommand(for: name, runtimes: runtimes).map { "missing: \(name): create it with \($0), or \(replace)" }
                    ?? "missing: \(name): no installed runtime supports it, so \(replace)"
            }.joined(separator: "; "))
        }
        let twoDisplays = wanted.filter { name in catalog.devices.contains { $0.name == name && catalog.hasTwoDisplays($0) } }
        if let name = twoDisplays.first {
            return .warn("\(name) has two displays, and MobileBuildMCP's screenshot fails on it: xcrew setup --test-simulator <name> picks another")
        }
        // MobileBuildMCP uses a profile's ID as it is, and tools like `screenshot` fail on one that's gone.
        let gone = ConfigRenderer.simulatorIDs(in: yaml).filter { id in !catalog.devices.contains { $0.udid == id } }
        guard gone.isEmpty else {
            return .warn("a simulator the profiles name by ID is gone (\(gone.joined(separator: ", "))): xcrew setup writes the current ones")
        }
        return .pass(wanted.joined(separator: ", "))
    }
}
