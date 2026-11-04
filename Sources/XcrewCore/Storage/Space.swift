import Foundation

/// `xcrew space`: what MobileBuildMCP and Xcode keep on this Mac, read from what each tool reports (docs/findings.md,
/// *Disk space*). Facts and the command that would reclaim each part only; it never deletes, never offers the selected or
/// the pinned Xcode, and never offers archives. It walks folders, so it runs only when asked, never on the prompt line.
public enum Space {
    /// The age a dry run of `purge` and of `simctl runtime delete` is named with.
    static let days = 30

    public static func report(project: Project, machine: Machine) async -> SpaceReport {
        let now = machine.now()
        let live = Task { await ProjectWorkspaces.live(of: project, using: machine.runner) }
        async let derivedData = derivedDataFolder(machine: machine)
        async let mobile = mobileBuildMCP(live: live, machine: machine, now: now)
        async let runtimes = runtimes(machine: machine, now: now)
        async let devices = devices(machine: machine)
        async let xcodes = xcodes(project: project, machine: machine)
        let folder = await derivedData
        async let derived = xcodeDerivedData(in: folder, live: live, machine: machine)
        async let others = others(derivedData: folder, machine: machine)
        async let worktrees = worktreePart(CheckContext(project: project, machine: machine))
        let parts: [SpaceReport.Part?] = [await mobile, await derived, await runtimes, await devices, await worktrees, await xcodes, await others]
        return SpaceReport(parts: parts.compactMap(\.self))
    }

    /// The simulators `setup --worktree` made: those left behind, each with the command that removes it, or that none is.
    /// None when the project isn't in git or setup recorded none.
    static func worktreePart(_ context: CheckContext) async -> SpaceReport.Part? {
        let found = await WorktreeLeftovers.run(context)
        guard found.status != .skip else { return nil }
        return SpaceReport.Part(title: "Simulators setup made for worktrees", lines: [SpaceReport.Line(text: found.message)])
    }

    // MARK: MobileBuildMCP

    /// What follows each `--dry-run`, said once.
    static let purgeNote = "Each `--dry-run` lists what it would delete. Deleting loses those builds, logs and results, so it's the person's to agree to: `--delete` in place of `--dry-run`, with `--confirm delete-mobilebuildmcp-storage`"

    /// The dry run of `purge` for one workspace's `classes`; none for none.
    static func purge(_ workspace: StorageReport.Workspace, classes: [String]) -> String? {
        classes.isEmpty ? nil : "mobilebuildmcp purge --dry-run --scope workspace --workspace-key \(workspace.key) --classes \(classes.joined(separator: ","))"
    }

    /// A workspace's classes that exist and may be deleted, the cheapest to make again first: test products, which the
    /// next test run makes again, then the rest, then DerivedData, which costs a cold build (docs/findings.md, *Disk space*).
    static func reclaimable(_ workspace: StorageReport.Workspace) -> [String] {
        let rank = { (name: String) in name == "testProducts" ? 0 : name == "derivedData" ? 2 : 1 }
        return StorageReport.reclaimable(workspace).sorted { (rank($0), $0) < (rank($1), $1) }
    }

    /// The `.xctestproducts` bundles in a workspace's test products, one per test run; 0 when it can't be read.
    static func bundles(in workspace: StorageReport.Workspace, machine: Machine) -> Int {
        let folder = URL(fileURLWithPath: ToolOutput.expandingHome(workspace.folder, home: machine.home.path) + "/test-products")
        return (machine.files.names(in: folder) ?? []).count { $0.hasSuffix(".xctestproducts") }
    }

    /// Whether an xcodebuild is writing to a workspace's DerivedData now: its figure is that build's too.
    static func isBuilding(into workspace: StorageReport.Workspace, processes: ProcessList, home: URL) -> Bool {
        let folder = ProjectLayout.canonicalPath(ToolOutput.expandingHome(workspace.folder, home: home.path)) + "/"
        return processes.processes.contains { $0.isXcodebuild && !$0.asksOnly && ($0.derivedDataPath.map { ($0 + "/").hasPrefix(folder) } ?? false) }
    }

    /// One of this project's workspaces: its size, its test products counted in bundles, its DerivedData, and the dry
    /// run of everything but DerivedData; then its DerivedData apart, with its own dry run, since it costs a cold build.
    static func workspaceLines(_ workspace: StorageReport.Workspace, name: String, root: String, newest: String?, bundles: Int, isBuilding: Bool) -> [SpaceReport.Line] {
        let present = { (name: String) in workspace.classes[name].flatMap { $0.exists && $0.bytes > 0 ? $0.bytes : nil } }
        let products = present("testProducts").map { bytes in
            ", test products \(SpaceReport.size(bytes))" + (bundles > 0 ? " in \(counted(bundles, "bundle")) of about \(SpaceReport.size(bytes / bundles)) each" : "")
        } ?? ""
        let derived = present("derivedData")
        let building = isBuilding ? "; a build is writing to its DerivedData now" : ""
        let classes = reclaimable(workspace)
        let line = SpaceReport.Line(text: "\(name), \(root): \(SpaceReport.size(workspace.bytes))\(products)\(derived.map { ", DerivedData \(SpaceReport.size($0))" } ?? "")\(newest.map { ", newest \($0)" } ?? "")\(building)", bytes: workspace.bytes, command: purge(workspace, classes: classes.filter { $0 != "derivedData" }))
        guard let derived, classes.contains("derivedData") else { return [line] }
        return [line, .init(text: "\(name)'s DerivedData, \(SpaceReport.size(derived)), costs a cold build to make again, so deleting it is the person's to agree to", bytes: derived, command: purge(workspace, classes: ["derivedData"]))]
    }

    /// How long MobileBuildMCP's purge keeps a log after it's written (`WORKSPACE_FILESYSTEM_LIFECYCLE_MIN_VISIBLE_MS`).
    static let logsKeptFor: TimeInterval = 3600

    /// The workspaces whose project is gone, each with the purge's dry run, unless all it holds is what the purge keeps:
    /// logs written within `logsKeptFor`, and its state, and its folder, which the purge never removes. Those are counted on
    /// one line with no command; a purge an hour on takes the logs (docs/findings.md, *Disk space*).
    static func goneLines(_ gone: [(workspace: StorageReport.Workspace, root: String)], now: Date) -> [SpaceReport.Line] {
        let isKept = { (workspace: StorageReport.Workspace) in
            workspace.classes.allSatisfy { name, found in
                !found.exists || found.bytes == 0 || name == "locks" || name == "stateTransients" || (name == "logs" && found.newest.map { now.timeIntervalSince($0) < logsKeptFor } == true)
            }
        }
        let named = gone.filter { !isKept($0.workspace) }.map { workspace, root in
            SpaceReport.Line(text: "\(workspace.key): \(SpaceReport.size(workspace.bytes)); its project, \(root), is gone", bytes: workspace.bytes, command: purge(workspace, classes: reclaimable(workspace)))
        }
        let kept = gone.filter { isKept($0.workspace) }.map(\.workspace.bytes)
        guard !kept.isEmpty else { return named }
        let bytes = kept.reduce(0, +)
        return named + [.init(text: "\(kept.count) gone \(kept.count == 1 ? "project's folder holds" : "projects' folders hold") only what `mobilebuildmcp purge` keeps: \(SpaceReport.size(bytes))", bytes: bytes)]
    }

    static func mobileBuildMCP(live: Task<[ProjectWorkspaces.Checkout], Never>, machine: Machine, now: Date) async -> SpaceReport.Part {
        let title = "MobileBuildMCP"
        guard let report = await StorageReport.read(.all, using: machine.runner) else { return SpaceReport.notRead(title, by: "mobilebuildmcp purge --report") }
        let grouped = ProjectWorkspaces.grouped(report, origins: await ProjectWorkspaces.origins(of: report, live: await live.value, machine: machine))
        let processes = grouped.live.isEmpty ? ProcessList(ps: "") : await ProcessList.load(using: machine.runner)
        var lines: [SpaceReport.Line] = grouped.live.isEmpty ? [] : [.init(text: ProjectStorage.line(grouped.live, machine: machine, processes: processes))]
        lines += grouped.live.flatMap { workspace, checkout in
            workspaceLines(workspace, name: URL(fileURLWithPath: checkout.root).lastPathComponent, root: checkout.root, newest: workspace.classes.values.compactMap(\.newest).max().map { SpaceReport.age(of: $0, now: now) },
                           bundles: bundles(in: workspace, machine: machine), isBuilding: isBuilding(into: workspace, processes: processes, home: machine.home))
        }
        lines += goneLines(grouped.gone, now: now)
        let (elsewhere, unknown) = (grouped.elsewhere, grouped.unknown)
        lines += [
            rollup(elsewhere.map(\.bytes), "workspace", "of other projects still here"),
            rollup(unknown.map(\.bytes), "workspace", "whose project isn't known", then: "; `mobilebuildmcp purge --report --json` lists each"),
        ].compactMap(\.self)
        return .init(title: title, lines: lines, note: purgeNote)
    }

    /// `3 workspaces whose project isn't known: 3.3 MB`; none for none.
    static func rollup(_ sizes: [Int], _ noun: String, _ what: String, then: String = "") -> SpaceReport.Line? {
        guard !sizes.isEmpty else { return nil }
        let bytes = sizes.reduce(0, +)
        return .init(text: "\(counted(sizes.count, noun)) \(what): \(SpaceReport.size(bytes))\(then)", bytes: bytes)
    }

    /// `1 module`, `2 modules`: a count with its noun, plural past one.
    public static func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    // MARK: Xcode's DerivedData

    /// Where Xcode keeps DerivedData: its `IDECustomDerivedDataLocation` when it names a folder, else the default.
    /// A relative one is beside each workspace, so no one folder holds it.
    enum DerivedDataFolder: Sendable {
        case folder(URL)
        case besideEachWorkspace(String)
    }

    static func derivedDataFolder(machine: Machine) async -> DerivedDataFolder {
        let custom = await machine.runner.run("defaults", "read", "com.apple.dt.Xcode", "IDECustomDerivedDataLocation")
        let named = custom.succeeded ? custom.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if named.isEmpty { return .folder(machine.home.appending(path: "Library/Developer/Xcode/DerivedData")) }
        return named.hasPrefix("/") ? .folder(URL(fileURLWithPath: named)) : .besideEachWorkspace(named)
    }

    /// Xcode's DerivedData, by the workspace each folder's `info.plist` names: those whose workspace is gone, this
    /// project's, and the rest together. No tool reclaims these, and the routing keeps DerivedData the person's to delete.
    static func xcodeDerivedData(in location: DerivedDataFolder, live: Task<[ProjectWorkspaces.Checkout], Never>, machine: Machine) async -> SpaceReport.Part? {
        let title = "Xcode's DerivedData"
        guard case let .folder(folder) = location else {
            guard case let .besideEachWorkspace(named) = location else { return nil }
            return .init(title: title, lines: [.init(text: "not read: Xcode keeps DerivedData in each workspace's folder (`\(named)`)")])
        }
        struct Info: Decodable {
            let WorkspacePath: String
        }
        let entries = (machine.files.names(in: folder) ?? []).map { folder.appending(path: $0) }.compactMap { entry -> (URL, String)? in
            guard let data = machine.files.data(at: entry.appending(path: "info.plist")),
                  let info = try? PropertyListDecoder().decode(Info.self, from: data)
            else { return nil }
            return (entry, info.WorkspacePath)
        }.sorted { $0.0.lastPathComponent < $1.0.lastPathComponent }
        guard !entries.isEmpty else { return nil }
        let sizes = await sizes(of: entries.map(\.0.path), using: machine.runner, measuring: du)
        let roots = await live.value.flatMap { [$0.root, ProjectLayout.canonicalPath($0.root)] }
        var lines: [SpaceReport.Line] = []
        var others: [Int] = []
        for (entry, workspace) in entries {
            let size = sizes[entry.path].map(SpaceReport.size) ?? "not measured"
            if !machine.files.exists(URL(fileURLWithPath: workspace)) {
                lines.append(.init(text: "\(entry.lastPathComponent): \(size); its workspace, \(workspace), is gone", bytes: sizes[entry.path]))
            } else if roots.contains(where: { workspace == $0 || workspace.hasPrefix($0 + "/") }) {
                lines.append(.init(text: "\(entry.lastPathComponent), for this project: \(size)", bytes: sizes[entry.path]))
            } else {
                others.append(sizes[entry.path] ?? 0)
            }
        }
        if let rest = rollup(others, "folder", "for other projects") { lines.append(rest) }
        return .init(title: title, lines: lines, note: "In \(folder.path); Xcode's Settings → Locations names it. Nothing here deletes it.")
    }

    /// How many folders or files are measured at once, so their walks don't fight over the disk.
    static let measuredAtOnce = 4

    /// Each path's size by `measure`, a few at a time; one it couldn't size is missing.
    static func sizes(of paths: [String], using runner: any CommandRunning, measuring measure: @escaping @Sendable (String, any CommandRunning) async -> Int?) async -> [String: Int] {
        await withTaskGroup(of: (String, Int?).self) { group in
            var pending = paths.makeIterator()
            func next() {
                guard let path = pending.next() else { return }
                group.addTask { (path, await measure(path, runner)) }
            }
            for _ in 0..<measuredAtOnce { next() }
            var sizes: [String: Int] = [:]
            while let (path, size) = await group.next() {
                sizes[path] = size
                next()
            }
            return sizes
        }
    }

    /// A folder's size from `du -sk`.
    static let du: @Sendable (String, any CommandRunning) async -> Int? = { path, runner in
        let ran = await runner.run(["du", "-sk", path], stdin: nil)
        return ran.succeeded ? ran.stdout.split(separator: "\t").first.flatMap { Int($0) }.map { $0 * 1024 } : nil
    }

    /// An app's size from Spotlight, at once where `du` would walk it.
    static let spotlight: @Sendable (String, any CommandRunning) async -> Int? = { path, runner in
        Int(await runner.run("mdls", "-raw", "-name", "kMDItemPhysicalSize", path).stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Simulators

    static func runtimes(machine: Machine, now: Date) async -> SpaceReport.Part {
        let title = "Simulator runtimes"
        let listed = await machine.runner.run("xcrun", "simctl", "runtime", "list", "-j")
        guard listed.succeeded, let images = (try? JSONSerialization.jsonObject(with: Data(listed.stdout.utf8))) as? [String: [String: Any]] else {
            return SpaceReport.notRead(title, by: "xcrun simctl runtime list")
        }
        let read = ISO8601DateFormatter()
        let lines = images.values.map { image -> SpaceReport.Line in
            let platform = (image["runtimeIdentifier"] as? String)?.split(separator: ".").last?.split(separator: "-").first.map(String.init) ?? "Runtime"
            let bytes = image["sizeBytes"] as? Int ?? 0
            let used = (image["lastUsedAt"] as? String).flatMap(read.date(from:)).map { "last used \(SpaceReport.age(of: $0, now: now))" } ?? "no last use recorded"
            return .init(text: "\(platform) \(image["version"] as? String ?? "?") (\(image["build"] as? String ?? "?")): \(SpaceReport.size(bytes)), \(used)", bytes: bytes)
        }.sorted { ($0.bytes ?? 0, $0.text) > ($1.bytes ?? 0, $1.text) }
        return .init(title: title, lines: lines, command: "xcrun simctl runtime delete --notUsedSinceDays \(days) --dry-run")
    }

    static func devices(machine: Machine) async -> SpaceReport.Part {
        let title = "Simulator devices"
        let listed = await machine.runner.run("xcrun", "simctl", "list", "devices", "-j")
        guard listed.succeeded, let object = (try? JSONSerialization.jsonObject(with: Data(listed.stdout.utf8))) as? [String: Any],
              let byRuntime = object["devices"] as? [String: [[String: Any]]]
        else { return SpaceReport.notRead(title, by: "xcrun simctl list devices") }
        let devices = byRuntime.values.joined()
        let bytes = devices.reduce(0) { $0 + ($1["dataPathSize"] as? Int ?? 0) }
        let unavailable = devices.filter { ($0["isAvailable"] as? Bool) == false }.count
        return .init(title: title, lines: [Self.devicesLine(devices: devices.count, bytes: bytes, unavailable: unavailable)])
    }

    /// The devices' line: how many and their data, and the unavailable ones, whose delete loses the apps on them and their
    /// data, the person's call, said before the command, which `SpaceReport` prints on the line below.
    static func devicesLine(devices: Int, bytes: Int, unavailable: Int) -> SpaceReport.Line {
        let text = "\(counted(devices, "device")): \(SpaceReport.size(bytes)) of data"
            + (unavailable > 0 ? ", \(unavailable) unavailable. Deleting the unavailable \(unavailable == 1 ? "one" : "ones") \(SimulatorDelete.loses(unavailable == 1 ? "it" : "them")):" : "")
        return .init(text: text, bytes: bytes, command: unavailable > 0 ? "xcrun simctl delete unavailable" : nil)
    }

    // MARK: Xcodes

    /// Each installed Xcode's size from Spotlight. `xcodes uninstall` names a version, so it's offered only for an Xcode
    /// neither selected nor pinned whose version no other install shares, and only with `xcodes` installed.
    static func xcodes(project: Project, machine: Machine) async -> SpaceReport.Part? {
        async let installed = Xcodes.installed(on: machine)
        async let selected = Xcodes.selected(on: machine)
        let all = await installed
        guard !all.isEmpty else { return nil }
        let chosen = await selected
        let pinned = project.xcodePin.flatMap { Xcodes.matching($0.version, in: all) }
        let canUninstall = machine.runner.which("xcodes") != nil
        let sizes = await sizes(of: all.map(\.path), using: machine.runner, measuring: spotlight)
        let lines = all.map { xcode -> SpaceReport.Line in
            let same = { (other: XcodeInstall?) in other.map { ProjectLayout.canonicalPath($0.path) == ProjectLayout.canonicalPath(xcode.path) } == true }
            let roles = [same(chosen) ? "selected" : nil, same(pinned) ? "pinned" : nil].compactMap(\.self)
            let alone = all.filter { $0.version == xcode.version }.count == 1
            let offered = roles.isEmpty && alone && canUninstall
            return Self.xcodeLine("\(xcode.label)\(roles.isEmpty ? "" : ", " + roles.joined(separator: " and ")): \(sizes[xcode.path].map(SpaceReport.size) ?? "size not known")", bytes: sizes[xcode.path], offering: offered ? xcode.version : nil)
        }
        return .init(title: "Xcodes", lines: lines)
    }

    /// An Xcode's line, and when `version` is offered, the uninstall that removes it, the person's call, said before the
    /// command `SpaceReport` prints on the line below.
    static func xcodeLine(_ text: String, bytes: Int?, offering version: String?) -> SpaceReport.Line {
        .init(text: text + (version == nil ? "" : ". Uninstalling it removes that Xcode, so it's the person's to agree to:"), bytes: bytes, command: version.map { "xcodes uninstall \($0)" })
    }

    // MARK: Other folders

    /// Folders no tool sizes or reclaims for xcrew: sizes only. Archives are the person's builds and are never offered.
    static func others(derivedData: DerivedDataFolder, machine: Machine) async -> SpaceReport.Part? {
        let developer = machine.home.appending(path: "Library/Developer/Xcode")
        let moduleCache: [(String, URL)] = if case let .folder(folder) = derivedData { [("Module cache", folder.appending(path: "ModuleCache.noindex"))] } else { [] }
        let folders: [(String, URL)] = (moduleCache + [
            ("Device support", developer.appending(path: "iOS DeviceSupport")),
            ("Archives", developer.appending(path: "Archives")),
            ("Previews", developer.appending(path: "UserData/Previews")),
            ("SwiftPM's cache", machine.home.appending(path: "Library/Caches/org.swift.swiftpm")),
            ("xcrew's cache (its launcher removes a build unused for \(FailureImages.keptDays) days)", machine.cacheFolder),
        ]).filter { machine.files.exists($0.1) }
        guard !folders.isEmpty else { return nil }
        let sizes = await sizes(of: folders.map(\.1.path), using: machine.runner, measuring: du)
        return .init(title: "Other folders", lines: folders.map { name, folder in
            .init(text: "\(name): \(sizes[folder.path].map(SpaceReport.size) ?? "not measured")", bytes: sizes[folder.path])
        })
    }
}
