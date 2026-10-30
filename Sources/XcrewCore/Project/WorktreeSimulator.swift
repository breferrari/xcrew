import Foundation

/// A linked worktree's simulator of its own, so agents in two worktrees don't install their builds over each other's or
/// tap through one screen. Made on the device type and runtime of the simulator the main checkout's profile names, and
/// never booted: MobileBuildMCP boots it on first use (docs/findings.md, *Worktree sessions*).
public enum WorktreeSimulator {
    /// What marks a simulator as one xcrew made for a worktree, so a person's own is never taken for one.
    public static let prefix = "xcrew · "

    /// The simulator's name: the prefix, the main checkout's folder, and the worktree's.
    public static func name(main: URL, worktree: URL) -> String {
        "\(prefix)\(main.lastPathComponent) · \(worktree.lastPathComponent)"
    }

    /// The keys a MobileBuildMCP profile names its simulator by.
    static let keys = ["simulatorId", "simulatorName"]

    /// The worktree's config with its own simulator in place of the main checkout's, and what setup says of it: a
    /// simulator made for it earlier is used again, and none is made when the main checkout names none or one this Mac
    /// doesn't have. Nothing is said when there's nothing to say.
    public static func make(for worktree: URL, main: URL, config yaml: String, using runner: any CommandRunning) async -> (yaml: String, line: String?) {
        guard let named = named(in: yaml) else { return (yaml, nil) }
        let catalog = await SimulatorCatalog.load(using: runner)
        guard let source = catalog.devices.first(where: { named.key == "simulatorId" ? $0.udid == named.value : $0.name == named.value }),
              let deviceType = source.deviceType, let runtime = source.runtime
        else { return (yaml, "xcrew: the main checkout's simulator, \(named.value), isn't on this Mac, so none was made for this worktree; its profile names that one") }
        let name = name(main: main, worktree: worktree)
        let label = "\(typeName(deviceType)), \(source.platform) \(source.runtimeVersion)"
        if let earlier = catalog.devices.first(where: { $0.name == name })?.udid {
            return (naming(earlier, in: yaml), "xcrew: this worktree uses simulator `\(name)` (\(label)), made for it earlier")
        }
        let created = await runner.run("xcrun", "simctl", "create", name, deviceType, runtime)
        let udid = created.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard created.succeeded, !udid.isEmpty else {
            let why = created.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return (yaml, "xcrew: couldn't create a simulator for this worktree (xcrun simctl create: \(why.isEmpty ? "no answer" : why)); its profile names the main checkout's")
        }
        return (naming(udid, in: yaml), "xcrew: created simulator `\(name)` (\(label)) for this worktree")
    }

    /// The first simulator the config names, and by which key.
    static func named(in yaml: String) -> (key: String, value: String)? {
        for line in yaml.split(separator: "\n") {
            for key in keys {
                if let value = ConfigRenderer.value(of: key, in: line), !value.isEmpty { return (key, value) }
            }
        }
        return nil
    }

    /// The config with every simulator it names replaced by `udid`, by id.
    static func naming(_ udid: String, in yaml: String) -> String {
        yaml.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            guard keys.contains(where: { ConfigRenderer.value(of: $0, in: line) != nil }) else { return String(line) }
            return String(line.prefix { $0 == " " }) + "simulatorId: " + ConfigRenderer.quoted(udid)
        }.joined(separator: "\n")
    }

    /// A device type's name as its identifier spells it: `iPhone 18 Pro` for `….SimDeviceType.iPhone-18-Pro`.
    static func typeName(_ identifier: String) -> String {
        (identifier.split(separator: ".").last.map(String.init) ?? identifier).replacingOccurrences(of: "-", with: " ")
    }
}
