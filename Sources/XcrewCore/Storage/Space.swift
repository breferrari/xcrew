import Foundation

/// `xcrew space`: what MobileBuildMCP and Xcode keep on this Mac, read from what each tool reports (docs/findings.md,
/// *Disk space*). Facts and the command that would reclaim each part only; it never deletes, never offers the selected or
/// the pinned Xcode, and never offers archives. It walks folders, so it runs only when asked, never on the prompt line.
public enum Space {
    /// How long one folder's `du` may take before its size is left unmeasured.
    static let folderTimeout = Duration.seconds(30)
    /// The age a dry run of `purge` and of `simctl runtime delete` is named with.
    static let days = 30

    public static func report(project: Project, machine: Machine, now: Date = Date()) async -> SpaceReport {
        let live = Task { await ProjectWorkspaces.live(of: project, using: machine.runner) }
        async let derivedData = derivedDataFolder(machine: machine)
        async let mobile = mobileBuildMCP(live: live, machine: machine, now: now)
        async let runtimes = runtimes(machine: machine, now: now)
        async let devices = devices(machine: machine)
        async let xcodes = xcodes(project: project, machine: machine)
        let folder = await derivedData
        async let derived = xcodeDerivedData(in: folder, live: live, machine: machine)
        async let others = others(derivedData: folder, machine: machine)
        let parts: [SpaceReport.Part?] = [await mobile, await derived, await runtimes, await devices, await xcodes, await others]
        return SpaceReport(parts: parts.compactMap(\.self))
    }

    // MARK: MobileBuildMCP

    /// What follows each `--dry-run`, said once.
    static let purgeNote = "Each `--dry-run` lists what it would delete; with `--delete` in its place and `--confirm delete-mobilebuildmcp-storage`, it deletes."

    /// The dry run of `purge` for one workspace's classes that exist and may be deleted; none when it has none.
    static func purge(_ workspace: StorageReport.Workspace) -> String? {
        let classes = StorageReport.reclaimable(workspace)
        return classes.isEmpty ? nil : "mobilebuildmcp purge --dry-run --scope workspace --workspace-key \(workspace.key) --classes \(classes.joined(separator: ","))"
    }

    static func mobileBuildMCP(live: Task<[ProjectWorkspaces.Checkout], Never>, machine: Machine, now: Date) async -> SpaceReport.Part {
        let title = "MobileBuildMCP"
        guard let report = await StorageReport.read(.all, using: machine.runner) else { return SpaceReport.notRead(title, by: "mobilebuildmcp purge --report") }
        let grouped = ProjectWorkspaces.grouped(report, origins: await ProjectWorkspaces.origins(of: report, live: await live.value, home: machine.home))
        var lines: [SpaceReport.Line] = grouped.live.map { workspace, checkout in
            let name = URL(fileURLWithPath: checkout.root).lastPathComponent
            let derived = workspace.classes["derivedData"].flatMap { $0.exists && $0.bytes > 0 ? ", DerivedData \(SpaceReport.size($0.bytes))" : nil } ?? ""
            let newest = workspace.classes.values.compactMap(\.newest).max().map { ", newest \(SpaceReport.age(of: $0, now: now))" } ?? ""
            return .init(text: "\(name), \(checkout.root): \(SpaceReport.size(workspace.bytes))\(derived)\(newest)", bytes: workspace.bytes, command: purge(workspace))
        }
        lines += grouped.gone.map { workspace, root in
            .init(text: "\(workspace.key): \(SpaceReport.size(workspace.bytes)); its project, \(root), is gone", bytes: workspace.bytes, command: purge(workspace))
        }
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

    static func counted(_ count: Int, _ noun: String) -> String {
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
        let custom = await machine.runner.run("defaults", "read", "com.apple.dt.Xcode", "IDECustomDerivedDataLocation", timeout: .seconds(5))
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
        let entries = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).compactMap { entry -> (URL, String)? in
            guard let data = FileManager.default.contents(atPath: entry.appending(path: "info.plist").path),
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
            if !FileManager.default.fileExists(atPath: workspace) {
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

    /// A folder's size from `du -sk`, capped.
    static let du: @Sendable (String, any CommandRunning) async -> Int? = { path, runner in
        let ran = await runner.run(["du", "-sk", path], stdin: nil, timeout: folderTimeout)
        return ran.succeeded ? ran.stdout.split(separator: "\t").first.flatMap { Int($0) }.map { $0 * 1024 } : nil
    }

    /// An app's size from Spotlight, at once where `du` would walk it.
    static let spotlight: @Sendable (String, any CommandRunning) async -> Int? = { path, runner in
        Int(await runner.run("mdls", "-raw", "-name", "kMDItemPhysicalSize", path, timeout: .seconds(10)).stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Simulators

    static func runtimes(machine: Machine, now: Date) async -> SpaceReport.Part {
        let title = "Simulator runtimes"
        let listed = await machine.runner.run("xcrun", "simctl", "runtime", "list", "-j", timeout: .seconds(30))
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
        let listed = await machine.runner.run("xcrun", "simctl", "list", "devices", "-j", timeout: .seconds(30))
        guard listed.succeeded, let object = (try? JSONSerialization.jsonObject(with: Data(listed.stdout.utf8))) as? [String: Any],
              let byRuntime = object["devices"] as? [String: [[String: Any]]]
        else { return SpaceReport.notRead(title, by: "xcrun simctl list devices") }
        let devices = byRuntime.values.joined()
        let bytes = devices.reduce(0) { $0 + ($1["dataPathSize"] as? Int ?? 0) }
        let unavailable = devices.filter { ($0["isAvailable"] as? Bool) == false }.count
        let text = "\(counted(devices.count, "device")): \(SpaceReport.size(bytes)) of data" + (unavailable > 0 ? ", \(unavailable) unavailable" : "")
        return .init(title: title, lines: [.init(text: text, bytes: bytes, command: unavailable > 0 ? "xcrun simctl delete unavailable" : nil)])
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
            return .init(text: "\(xcode.label)\(roles.isEmpty ? "" : ", " + roles.joined(separator: " and ")): \(sizes[xcode.path].map(SpaceReport.size) ?? "size not known")", bytes: sizes[xcode.path], command: offered ? "xcodes uninstall \(xcode.version)" : nil)
        }
        return .init(title: "Xcodes", lines: lines)
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
        ]).filter { FileManager.default.fileExists(atPath: $0.1.path) }
        guard !folders.isEmpty else { return nil }
        let sizes = await sizes(of: folders.map(\.1.path), using: machine.runner, measuring: du)
        return .init(title: "Other folders", lines: folders.map { name, folder in
            .init(text: "\(name): \(sizes[folder.path].map(SpaceReport.size) ?? "not measured")", bytes: sizes[folder.path])
        })
    }
}
