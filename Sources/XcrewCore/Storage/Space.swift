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
        let live = await ProjectWorkspaces.live(of: project, using: machine.runner)
        async let mobile = mobileBuildMCP(live: live, machine: machine, now: now)
        async let derived = xcodeDerivedData(live: live, machine: machine)
        async let runtimes = runtimes(machine: machine, now: now)
        async let devices = devices(machine: machine)
        async let xcodes = xcodes(project: project, machine: machine)
        async let others = others(machine: machine)
        let parts: [SpaceReport.Part?] = [await mobile, await derived, await runtimes, await devices, await xcodes, await others]
        return SpaceReport(parts: parts.compactMap(\.self))
    }

    static func purge(_ scope: String) -> String {
        "mobilebuildmcp purge --dry-run \(scope)"
    }

    // MARK: MobileBuildMCP

    static func mobileBuildMCP(live: [ProjectWorkspaces.Checkout], machine: Machine, now: Date) async -> SpaceReport.Part {
        let title = "MobileBuildMCP"
        guard let report = await StorageReport.read(.all, using: machine.runner) else { return SpaceReport.notRead(title, by: "mobilebuildmcp purge --report") }
        let workspaces = machine.home.appending(path: "Library/Developer/MobileBuildMCP/workspaces")
        var lines: [SpaceReport.Line] = []
        var gone: [SpaceReport.Line] = []
        var here = (count: 0, bytes: 0), unknown = (count: 0, bytes: 0)
        for workspace in report.workspaces.sorted(by: { $0.bytes > $1.bytes }) {
            let scope = "--scope workspace --workspace-key \(workspace.key)"
            if let checkout = live.first(where: { $0.key == workspace.key }) {
                let name = URL(fileURLWithPath: checkout.root).lastPathComponent
                let derived = workspace.classes["derivedData"].flatMap { $0.exists && $0.bytes > 0 ? ", DerivedData \(SpaceReport.size($0.bytes))" : nil } ?? ""
                let newest = workspace.classes.values.compactMap(\.newest).max().map { ", newest \(SpaceReport.age(of: $0, now: now))" } ?? ""
                lines.append(.init(text: "\(name), \(checkout.root): \(SpaceReport.size(workspace.bytes))\(derived)\(newest)", bytes: workspace.bytes, command: purge(scope)))
            } else if let root = ProjectWorkspaces.root(ofWorkspace: workspaces.appending(path: workspace.key)) {
                if FileManager.default.fileExists(atPath: root) {
                    here = (here.count + 1, here.bytes + workspace.bytes)
                } else {
                    gone.append(.init(text: "\(workspace.key): \(SpaceReport.size(workspace.bytes)); its project, \(root), is gone", bytes: workspace.bytes, command: purge(scope)))
                }
            } else {
                unknown = (unknown.count + 1, unknown.bytes + workspace.bytes)
            }
        }
        lines += gone
        if here.count > 0 {
            lines.append(.init(text: "\(counted(here.count, "workspace")) of other projects still here: \(SpaceReport.size(here.bytes))", bytes: here.bytes))
        }
        if unknown.count > 0 {
            lines.append(.init(text: "\(counted(unknown.count, "workspace")) whose project isn't known: \(SpaceReport.size(unknown.bytes))", bytes: unknown.bytes, command: purge("--scope all --older-than \(days)d")))
        }
        return .init(title: title, lines: lines, note: "Each `--dry-run` lists what it would delete; `--delete` in its place deletes.")
    }

    static func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    // MARK: Xcode's DerivedData

    /// Xcode's DerivedData, by the workspace each folder's `info.plist` names: this project's, those whose workspace is
    /// gone, and the rest together. No tool reclaims these, and the routing keeps DerivedData the person's to delete.
    static func xcodeDerivedData(live: [ProjectWorkspaces.Checkout], machine: Machine) async -> SpaceReport.Part? {
        let custom = await machine.runner.run("defaults", "read", "com.apple.dt.Xcode", "IDECustomDerivedDataLocation", timeout: .seconds(5))
        let folder = custom.succeeded && !custom.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? URL(fileURLWithPath: custom.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            : machine.home.appending(path: "Library/Developer/Xcode/DerivedData")
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
        let sizes = await sizes(of: entries.map(\.0), using: machine.runner)
        let roots = live.flatMap { [$0.root, ProjectLayout.canonicalPath($0.root)] }
        var lines: [SpaceReport.Line] = []
        var others = (count: 0, bytes: 0)
        for (entry, workspace) in entries {
            let size = sizes[entry.path].map(SpaceReport.size) ?? "not measured"
            if roots.contains(where: { workspace.hasPrefix($0 + "/") }) {
                lines.append(.init(text: "\(entry.lastPathComponent), for this project: \(size)", bytes: sizes[entry.path]))
            } else if !FileManager.default.fileExists(atPath: workspace) {
                lines.append(.init(text: "\(entry.lastPathComponent): \(size); its workspace, \(workspace), is gone", bytes: sizes[entry.path]))
            } else {
                others = (others.count + 1, others.bytes + (sizes[entry.path] ?? 0))
            }
        }
        if others.count > 0 { lines.append(.init(text: "\(counted(others.count, "folder")) for other projects: \(SpaceReport.size(others.bytes))", bytes: others.bytes)) }
        return .init(title: "Xcode's DerivedData", lines: lines, note: "In \(folder.path); Xcode's Settings → Locations names it. Nothing here deletes it.")
    }

    /// Each folder's size from `du -sk`, at once, each capped; a folder `du` didn't size is missing.
    static func sizes(of folders: [URL], using runner: any CommandRunning) async -> [String: Int] {
        await withTaskGroup(of: (String, Int?).self) { group in
            for folder in folders {
                group.addTask {
                    let ran = await runner.run(["du", "-sk", folder.path], stdin: nil, timeout: folderTimeout)
                    return (folder.path, ran.succeeded ? ran.stdout.split(separator: "\t").first.flatMap { Int($0) }.map { $0 * 1024 } : nil)
                }
            }
            return await group.reduce(into: [:]) { sizes, sized in sizes[sized.0] = sized.1 }
        }
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

    /// Each installed Xcode's size from Spotlight. Only one neither selected nor pinned is offered, and only with `xcodes`.
    static func xcodes(project: Project, machine: Machine) async -> SpaceReport.Part? {
        async let installed = Xcodes.installed(on: machine)
        async let selected = Xcodes.selected(on: machine)
        let all = await installed
        guard !all.isEmpty else { return nil }
        let chosen = await selected
        let pinned = project.xcodePin.flatMap { Xcodes.matching($0.version, in: all) }
        let canUninstall = machine.runner.which("xcodes") != nil
        let sizes = await withTaskGroup(of: (String, Int?).self) { group in
            for xcode in all {
                group.addTask { (xcode.path, Int(await machine.runner.run("mdls", "-raw", "-name", "kMDItemPhysicalSize", xcode.path, timeout: .seconds(10)).stdout.trimmingCharacters(in: .whitespacesAndNewlines))) }
            }
            return await group.reduce(into: [String: Int]()) { sizes, sized in sizes[sized.0] = sized.1 }
        }
        let lines = all.map { xcode -> SpaceReport.Line in
            let same = { (other: XcodeInstall?) in other.map { ProjectLayout.canonicalPath($0.path) == ProjectLayout.canonicalPath(xcode.path) } == true }
            let roles = [same(chosen) ? "selected" : nil, same(pinned) ? "pinned" : nil].compactMap(\.self)
            let size = sizes[xcode.path].map(SpaceReport.size) ?? "size not known"
            let kept = !roles.isEmpty
            return .init(text: "\(xcode.label)\(kept ? ", " + roles.joined(separator: " and ") : ""): \(size)", bytes: sizes[xcode.path], command: kept || !canUninstall ? nil : "xcodes uninstall \(xcode.version)")
        }
        return .init(title: "Xcodes", lines: lines)
    }

    // MARK: Other folders

    /// Folders no tool sizes or reclaims for xcrew: sizes only. Archives are the person's builds and are never offered.
    static func others(machine: Machine) async -> SpaceReport.Part? {
        let developer = machine.home.appending(path: "Library/Developer/Xcode")
        let folders: [(String, URL)] = [
            ("Module cache", developer.appending(path: "DerivedData/ModuleCache.noindex")),
            ("Device support", developer.appending(path: "iOS DeviceSupport")),
            ("Archives", developer.appending(path: "Archives")),
            ("Previews", developer.appending(path: "UserData/Previews")),
            ("SwiftPM's cache", machine.home.appending(path: "Library/Caches/org.swift.swiftpm")),
            ("xcrew's cache (its launcher removes a build unused for 14 days)", machine.cacheFolder),
        ].filter { FileManager.default.fileExists(atPath: $0.1.path) }
        guard !folders.isEmpty else { return nil }
        let sizes = await sizes(of: folders.map(\.1), using: machine.runner)
        return .init(title: "Other folders", lines: folders.map { name, folder in
            .init(text: "\(name): \(sizes[folder.path].map(SpaceReport.size) ?? "not measured")", bytes: sizes[folder.path])
        })
    }
}
