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
        /// `failed <status>`: the CLI exited with another status.
        case failed(String)

        /// Why the server started without the pin, in the doctor's words; nothing when it started with it.
        public var reason: String? {
            switch self {
            case .applied: nil
            case .notBuilt: "the xcrew CLI wasn't built yet; it is once the session has started"
            case .noMatch: "no installed Xcode was the pinned one when it started"
            case let .timedOut(seconds): "the xcrew CLI took longer than \(seconds) s"
            case let .failed(status): "the xcrew CLI failed, with status \(status)"
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
        return matching(pin.version, in: (await spotlight(on: machine)).compactMap(install)).map(Pinned.installed) ?? .notInstalled
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

    /// The installed Xcode a pin names, by its version's numbers. A beta and a release share them (a beta's version reads
    /// plain `27.2`), so a pin with a beta's `b<n>` prefers an app named as a beta, one without prefers another, and
    /// among equals the first by path, wherever the list came from.
    public static func matching(_ pin: String, in installed: [XcodeInstall]) -> XcodeInstall? {
        let wantsBeta = pin.drop { $0.isNumber || $0 == "." }.lowercased().hasPrefix("b")
        let isBeta = { (install: XcodeInstall) in URL(fileURLWithPath: install.path).lastPathComponent.localizedCaseInsensitiveContains("beta") }
        return installed.filter { Version($0.version) == Version(pin) }.sorted { (isBeta($0) != wantsBeta ? 1 : 0, $0.path) < (isBeta($1) != wantsBeta ? 1 : 0, $1.path) }.first
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

    /// Each Xcode open, from the process list: the Xcode MCP works through it.
    static func running(in list: ProcessList) -> [XcodeInstall] {
        let suffix = "/Contents/MacOS/Xcode"
        return list.processes.map(\.programPath).filter { $0.hasSuffix(".app" + suffix) }.sorted()
            .compactMap { install(at: URL(fileURLWithPath: String($0.dropLast(suffix.count)))) }
    }

    /// The app a developer folder is in: `/Applications/Xcode.app` for `/Applications/Xcode.app/Contents/Developer`.
    static func app(holding developer: String) -> URL? {
        let parts = URL(fileURLWithPath: developer).pathComponents
        guard let index = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: Array(parts[...index])))
    }

    /// Where the launcher records it: xcrew's cache, below `launches` at the project's real path with a `.launch` suffix, as
    /// `bin/xcrew` keeps its keys below `roots`, so a project inside another has a record beside the other's folder.
    static func launchRecord(of project: Project, on machine: Machine) -> URL {
        URL(fileURLWithPath: machine.cacheFolder.path + "/launches" + project.canonicalRoot + ".launch")
    }

    /// The launcher's last record for the project.
    public static func launch(of project: Project, on machine: Machine) -> Launch? {
        lastLaunch(of: project, on: machine)?.launch
    }

    /// The record and when it was written: one older than the server running is an earlier start's.
    static func lastLaunch(of project: Project, on machine: Machine) -> (launch: Launch, written: Date)? {
        let record = launchRecord(of: project, on: machine)
        guard let text = try? String(contentsOf: record, encoding: .utf8), let line = GitHead.firstLine(text),
              let written = (try? FileManager.default.attributesOfItem(atPath: record.path))?[.modificationDate] as? Date,
              let launch = parse(line)
        else { return nil }
        return (launch, written)
    }

    static func parse(_ line: String) -> Launch? {
        if line.hasPrefix("applied ") { return .applied(String(line.dropFirst("applied ".count))) }
        if line.hasPrefix("timed out ") { return .timedOut(String(line.dropFirst("timed out ".count))) }
        if line.hasPrefix("failed ") { return .failed(String(line.dropFirst("failed ".count))) }
        return ["not built": Launch.notBuilt, "no match": .noMatch][line]
    }
}
