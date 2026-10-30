import Foundation

/// The Mac's Xcodes: those installed, the one selected, the ones open, which the Xcode MCP works through, and what the
/// MobileBuildMCP launcher did with the project's pin (docs/findings.md, *Which Xcode*).
public enum Xcodes {
    static let bundleIdentifier = "com.apple.dt.Xcode"

    /// What the launcher did with the project's pin when it last started the server, as it records it: the facts, which
    /// the doctor words.
    public enum Launch: Sendable, Equatable {
        /// `applied <developer folder>`: it set `DEVELOPER_DIR` to this folder.
        case applied(String)
        /// `not built`: the xcrew CLI had no build yet, and the launcher never starts one.
        case notBuilt
        /// `no match`: no installed Xcode was the pinned one.
        case noMatch
        /// `timed out <seconds>`: the CLI didn't answer within the launcher's limit.
        case timedOut(String)

        /// Why the server started without the pin, in the doctor's words; nothing when it started with it.
        public var reason: String? {
            switch self {
            case .applied: nil
            case .notBuilt: "the xcrew CLI wasn't built yet; it is once the session has started"
            case .noMatch: "no installed Xcode was the pinned one when it started"
            case let .timedOut(seconds): "the xcrew CLI took longer than \(seconds) s"
            }
        }
    }

    /// The installed Xcode a project's pin names, found the cheap way first, for the launcher: the applications folder,
    /// then Spotlight only when that has none.
    public enum Pinned: Sendable, Equatable {
        case none
        case notInstalled
        case installed(XcodeInstall)
    }

    /// Every installed Xcode, newest first: the apps in the applications folder and those Spotlight finds elsewhere,
    /// each once, each one whose bundle is Xcode's.
    public static func installed(on machine: Machine) async -> [XcodeInstall] {
        async let elsewhere = spotlight(on: machine)
        var seen = Set<String>()
        let apps = (applications(on: machine) + (await elsewhere)).filter { seen.insert(ProjectLayout.canonicalPath($0.path)).inserted }
        return apps.compactMap(install).sorted { Version($0.version) > Version($1.version) }
    }

    public static func pinned(in project: Project, on machine: Machine) async -> Pinned {
        guard let pin = project.xcodePin else { return .none }
        let listed = applications(on: machine).compactMap(install)
        if let match = matching(pin.version, in: listed) { return .installed(match) }
        return (await spotlight(on: machine)).compactMap(install).first { Version($0.version) == Version(pin.version) }.map(Pinned.installed) ?? .notInstalled
    }

    static func applications(on machine: Machine) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: machine.applications, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "app" }
    }

    static func spotlight(on machine: Machine) async -> [URL] {
        let found = await machine.runner.run(["mdfind", "kMDItemCFBundleIdentifier == '\(bundleIdentifier)'"], stdin: nil, timeout: .seconds(10))
        return found.succeeded ? found.stdout.split(whereSeparator: \.isNewline).map { URL(fileURLWithPath: String($0)) } : []
    }

    private struct Info: Decodable {
        let CFBundleIdentifier: String?
        let CFBundleShortVersionString: String?
    }

    private struct VersionInfo: Decodable {
        let ProductBuildVersion: String?
    }

    /// The Xcode at `app`, read from its `Info.plist` and `version.plist`; nothing when the app isn't Xcode.
    static func install(at app: URL) -> XcodeInstall? {
        let contents = app.appending(path: "Contents")
        guard let data = try? Data(contentsOf: contents.appending(path: "Info.plist")),
              let info = try? PropertyListDecoder().decode(Info.self, from: data),
              info.CFBundleIdentifier == bundleIdentifier, let version = info.CFBundleShortVersionString
        else { return nil }
        let build = (try? Data(contentsOf: contents.appending(path: "version.plist"))).flatMap { try? PropertyListDecoder().decode(VersionInfo.self, from: $0) }?.ProductBuildVersion
        return XcodeInstall(path: app.path, version: version, build: build ?? "")
    }

    /// The installed Xcode a pin names, by its version: a beta's `b<n>` and trailing zeros aside.
    public static func matching(_ pin: String, in installed: [XcodeInstall]) -> XcodeInstall? {
        installed.first { Version($0.version) == Version(pin) }
    }

    /// The Xcode builds use when nothing overrides it: the one `DEVELOPER_DIR` names, else `xcode-select`'s.
    public static func selected(on machine: Machine) async -> XcodeInstall? {
        var developer = machine.value("DEVELOPER_DIR")
        if developer == nil {
            let selected = await machine.runner.run(["xcode-select", "-p"], stdin: nil, timeout: .seconds(10))
            developer = selected.succeeded ? GitHead.firstLine(selected.stdout) : nil
        }
        return developer.flatMap(app(holding:)).flatMap(install)
    }

    /// Each Xcode open: the Xcode MCP works through it.
    public static func running(on machine: Machine) async -> [XcodeInstall] {
        let suffix = ".app/Contents/MacOS/Xcode"
        return await ProcessList.programs(using: machine.runner).values.sorted().filter { $0.hasSuffix(suffix) }
            .compactMap { install(at: URL(fileURLWithPath: String($0.dropLast(suffix.count - ".app".count)))) }
    }

    /// The app a developer folder is in: `/Applications/Xcode.app` for `/Applications/Xcode.app/Contents/Developer`.
    static func app(holding developer: String) -> URL? {
        let parts = URL(fileURLWithPath: developer).pathComponents
        guard let index = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: Array(parts[...index])))
    }

    /// Where the launcher records it: xcrew's cache, below `launches` at the project's real path, as `bin/xcrew` keeps
    /// its keys below `roots`.
    static func launchRecord(of project: Project, on machine: Machine) -> URL {
        URL(fileURLWithPath: machine.cacheFolder.path + "/launches" + project.canonicalRoot)
    }

    /// The launcher's last record for the project.
    public static func launch(of project: Project, on machine: Machine) -> Launch? {
        guard let text = try? String(contentsOf: launchRecord(of: project, on: machine), encoding: .utf8), let line = GitHead.firstLine(text) else { return nil }
        if line.hasPrefix("applied ") { return .applied(String(line.dropFirst("applied ".count))) }
        if line.hasPrefix("timed out ") { return .timedOut(String(line.dropFirst("timed out ".count))) }
        return ["not built": Launch.notBuilt, "no match": .noMatch][line]
    }
}
