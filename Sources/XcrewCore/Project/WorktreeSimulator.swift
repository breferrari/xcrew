import Foundation

/// A linked worktree's simulators of its own, so agents in two worktrees don't install their builds over each other's or
/// tap through one screen: a clone of the main checkout's while it's shut down, else one made fresh on its device type
/// and runtime, and never booted; MobileBuildMCP boots it on first use (docs/findings.md, *Worktree sessions*).
public enum WorktreeSimulator {
    /// What marks a simulator as one xcrew made for a worktree, so a person's own is never taken for one.
    public static let prefix = "xcrew · "

    /// The simulator's name: the prefix, then the main checkout's repository folder and the worktree's, so a project a
    /// folder down in its repository still names its worktree.
    public static func name(main: URL, worktree: URL) -> String {
        "\(prefix)\(main.lastPathComponent) · \(worktree.lastPathComponent)"
    }

    /// The keys a MobileBuildMCP profile names its simulator by.
    static let keys = ["simulatorId", "simulatorName"]

    /// The simulator lines of one mapping (a profile, or the global defaults), by line, and what they name.
    struct Mapping {
        var lines: [Int] = []
        var id: String?
        var name: String?
    }

    /// The worktree's config with simulators of its own in place of the main checkout's, and what setup says of them.
    /// `main` and `worktree` are the two repositories' top folders, which the names come from. Each simulator the
    /// profiles use gets one, named by its device type when they use more than one: a clone of it while it's shut down,
    /// with its apps and data, else one made fresh on its device type and runtime, as always with `fresh`; one made
    /// earlier is used again, found by `record` before its name; none is made for one this Mac doesn't have. A mapping
    /// that named its simulator twice, by name and by id, names its own once, by id. Each it uses is added to `record`.
    public static func make(for worktree: URL, main: URL, config yaml: String, fresh: Bool, record file: URL? = nil, using runner: any CommandRunning) async -> (yaml: String, lines: [String]) {
        var lines = yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let mappings = mappings(in: lines)
        guard !mappings.isEmpty else { return (yaml, []) }
        let catalog = await SimulatorCatalog.load(using: runner)
        // Each mapping's simulator, by the id it names when it names one: a name may be on two runtimes.
        let sources = mappings.map { mapping in
            (mapping.id ?? mapping.name.flatMap(catalog.udid(of:))).flatMap { udid in catalog.devices.first { $0.udid == udid } }
        }
        var said: [String] = []
        for (mapping, source) in zip(mappings, sources) where source == nil {
            let named = mapping.name ?? mapping.id ?? ""
            let line = "xcrew: the main checkout's simulator, \(named), isn't on this Mac, so none was made for it in this worktree; its profile names that one"
            if !said.contains(line) { said.append(line) }
        }
        var distinct: [SimulatorCatalog.Device] = []
        for case let source? in sources where !distinct.contains(where: { $0.udid == source.udid }) { distinct.append(source) }
        let base = name(main: main, worktree: worktree)
        var record = file.map(WorktreeSimulatorRecord.read) ?? WorktreeSimulatorRecord()
        let recorded = Set(record.entries.filter { $0.worktree == ProjectLayout.canonical(worktree) }.map(\.udid))
        var made: [String: String] = [:]
        defer {
            if let file, !made.isEmpty {
                for udid in Set(made.values) { record = record.adding(udid, for: worktree) }
                try? record.write(to: file)
            }
        }
        for source in distinct {
            guard let deviceType = source.deviceType, let runtime = source.runtime, let from = source.udid else { continue }
            let name = distinct.count > 1 ? "\(base) · \(typeName(deviceType))" : base
            let label = "\(typeName(deviceType)), \(source.platform) \(source.runtimeVersion)"
            let mine = catalog.devices.first { $0.udid.map(recorded.contains) == true && $0.deviceType == deviceType }
            if let earlier = mine ?? catalog.devices.first(where: { $0.name == name }), let udid = earlier.udid {
                made[from] = udid
                let clean = fresh ? "; `xcrun simctl delete \(udid)` and setup again make a fresh one" : ""
                said.append("xcrew: this worktree uses simulator `\(earlier.name)` (\(label)), made for it earlier\(clean)")
                continue
            }
            var notCloned: String?
            if !fresh {
                if source.state == "Shutdown" {
                    let cloned = await runner.run("xcrun", "simctl", "clone", from, name)
                    let udid = cloned.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cloned.succeeded, !udid.isEmpty {
                        made[from] = udid
                        said.append("xcrew: cloned simulator `\(name)` (\(label)) from \(source.name), with its apps and data, for this worktree")
                        continue
                    }
                    let why = cloned.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    notCloned = "cloning \(source.name) failed (\(why.isEmpty ? "no answer" : why))"
                } else {
                    let state = source.state == "Booted" ? "is booted" : "isn't shut down (\(source.state ?? "its state unknown"))"
                    notCloned = "\(source.name) \(state), and only a shut-down simulator can be cloned"
                }
            }
            let created = await runner.run("xcrun", "simctl", "create", name, deviceType, runtime)
            let udid = created.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard created.succeeded, !udid.isEmpty else {
                let why = created.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                said.append("xcrew: couldn't create `\(name)` for this worktree (xcrun simctl create: \(why.isEmpty ? "no answer" : why)); its profile names the main checkout's simulator")
                continue
            }
            made[from] = udid
            said.append("xcrew: created simulator `\(name)` (\(label)) " + (notCloned.map { "fresh for this worktree: \($0)" } ?? "for this worktree"))
        }
        var dropped = Set<Int>()
        for (mapping, source) in zip(mappings, sources) {
            guard let from = source?.udid, let udid = made[from], let first = mapping.lines.first else { continue }
            lines[first] = String(lines[first].prefix { $0 == " " }) + "simulatorId: " + ConfigRenderer.quoted(udid)
            dropped.formUnion(mapping.lines.dropFirst())
        }
        return (lines.enumerated().filter { !dropped.contains($0.offset) }.map(\.element).joined(separator: "\n"), said)
    }

    /// The mappings that name a simulator, in the config's order: lines are one mapping's when the nearest line above them
    /// at a smaller indent is the same.
    static func mappings(in lines: [String]) -> [Mapping] {
        var byParent: [Int: Mapping] = [:]
        var order: [Int] = []
        for (index, line) in lines.enumerated() {
            guard let key = keys.first(where: { ConfigRenderer.value(of: $0, in: line).map { !$0.isEmpty } ?? false }), let value = ConfigRenderer.value(of: key, in: line) else { continue }
            let indent = line.prefix { $0 == " " }.count
            let parent = lines[..<index].lastIndex { above in
                let trimmed = above.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && !trimmed.hasPrefix("#") && above.prefix { $0 == " " }.count < indent
            } ?? -1
            if byParent[parent] == nil { order.append(parent) }
            byParent[parent, default: Mapping()].lines.append(index)
            if key == "simulatorId" { byParent[parent]?.id = value } else { byParent[parent]?.name = value }
        }
        return order.compactMap { byParent[$0] }
    }

    /// A device type's name as its identifier spells it: `iPhone 18 Pro` for `….SimDeviceType.iPhone-18-Pro`.
    static func typeName(_ identifier: String) -> String {
        (identifier.split(separator: ".").last.map(String.init) ?? identifier).replacingOccurrences(of: "-", with: " ")
    }
}
