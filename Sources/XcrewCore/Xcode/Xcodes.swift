import Foundation

/// Which Xcode a session's tools build with: those installed, the one selected, the project's pin, CI's, and the one
/// running, which the Xcode MCP works through (docs/findings.md, *Which Xcode*).
public enum Xcodes {
    /// An Xcode a CI workflow names: the file, the line, and its version; nil when the workflow picks the newest or a
    /// range, which can't be compared.
    public struct Named: Sendable, Equatable {
        public let file: String
        public let line: Int
        public let version: String?
    }

    static let bundleIdentifier = "com.apple.dt.Xcode"
    /// The pin, as xcodes' `XCODE_VERSION.md` names it: one version, beside the project or its workspace.
    public static let pinFile = ".xcode-version"

    private struct Info: Decodable {
        let CFBundleIdentifier: String?
        let CFBundleShortVersionString: String?
    }

    private struct VersionInfo: Decodable {
        let ProductBuildVersion: String?
    }

    /// Every installed Xcode, newest first: the apps in the applications folder and those Spotlight finds elsewhere,
    /// each one whose bundle is Xcode's.
    public static func installed(on machine: Machine) async -> [XcodeInstall] {
        let found = await machine.runner.run(["mdfind", "kMDItemCFBundleIdentifier == '\(bundleIdentifier)'"], stdin: nil, timeout: .seconds(10))
        let elsewhere = found.succeeded ? found.stdout.split(whereSeparator: \.isNewline).map { URL(fileURLWithPath: String($0)) } : []
        let listed = ((try? FileManager.default.contentsOfDirectory(at: machine.applications, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "app" }
        var seen = Set<String>()
        return (listed + elsewhere).compactMap(install).filter { seen.insert(ProjectLayout.canonicalPath($0.path)).inserted }.sorted { isNewer($0.version, than: $1.version) }
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

    /// The installed Xcode a pin names, by its version's numbers: a beta's `b<n>` and trailing zeros aside.
    public static func matching(_ pin: String, in installed: [XcodeInstall]) -> XcodeInstall? {
        installed.first { numbers($0.version) == numbers(pin) }
    }

    /// The project's pin and where it is: `.xcode-version` at the root, or beside one of its Xcode containers.
    public static func pin(of project: Project) -> (version: String, file: String)? {
        let folders = [""] + project.xcodeContainers.map { URL(fileURLWithPath: $0).deletingLastPathComponent().relativePath }.filter { $0 != "." }
        for folder in folders {
            let file = folder.isEmpty ? pinFile : "\(folder)/\(pinFile)"
            guard let text = try? String(contentsOf: project.root.appending(path: file), encoding: .utf8) else { continue }
            let version = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !version.isEmpty { return (version, file) }
        }
        return nil
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

    /// Each Xcode app running: the Xcode MCP works through the one open.
    public static func running(on machine: Machine) async -> [XcodeInstall] {
        let listed = await machine.runner.run(["ps", "-axo", "comm="], stdin: nil, timeout: .seconds(10))
        guard listed.succeeded else { return [] }
        let suffix = "/Contents/MacOS/Xcode"
        return listed.stdout.split(whereSeparator: \.isNewline).map(String.init).filter { $0.hasSuffix(".app\(suffix)") }
            .compactMap { install(at: URL(fileURLWithPath: String($0.dropLast(suffix.count)))) }
    }

    /// The Xcodes a project's GitHub Actions workflows name: setup-xcode's `xcode-version`, an `xcode-select -s` or
    /// `--switch` to an app, and a `DEVELOPER_DIR` inside one.
    public static func ci(of project: Project) -> [Named] {
        let folder = project.root.appending(path: ".github/workflows")
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".yml") || $0.hasSuffix(".yaml") }.sorted()
        return files.flatMap { name -> [Named] in
            let text = (try? String(contentsOf: folder.appending(path: name), encoding: .utf8)) ?? ""
            return text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { index, line in
                named(in: String(line)).map { Named(file: ".github/workflows/\(name)", line: index + 1, version: $0) }
            }
        }
    }

    /// What the MobileBuildMCP launcher did with the project's pin when it last started the server.
    public enum Launch: Sendable, Equatable {
        /// It set `DEVELOPER_DIR` to this developer folder.
        case applied(String)
        /// It started the server as without a pin, and why.
        case notApplied(String)
    }

    /// Where the launcher records it: xcrew's cache, below `launches` at the project's real path, as `bin/xcrew` keeps
    /// its keys below `roots`.
    static func launchRecord(of project: Project, on machine: Machine) -> URL {
        URL(fileURLWithPath: machine.cacheFolder.path + "/launches" + project.canonicalRoot)
    }

    /// The launcher's last record for the project: `applied <developer folder>` or `not applied: <why>`.
    public static func launch(of project: Project, on machine: Machine) -> Launch? {
        guard let text = try? String(contentsOf: launchRecord(of: project, on: machine), encoding: .utf8), let line = GitHead.firstLine(text) else { return nil }
        if line.hasPrefix("applied ") { return .applied(String(line.dropFirst("applied ".count))) }
        if line.hasPrefix("not applied: ") { return .notApplied(String(line.dropFirst("not applied: ".count))) }
        return nil
    }

    /// The Xcode MobileBuildMCP builds with: the pin's, when its server started with it, else the selected one.
    public static func forBuilds(of project: Project, on machine: Machine) async -> XcodeInstall? {
        if case let .applied(developer) = launch(of: project, on: machine), let install = app(holding: developer).flatMap(install) { return install }
        return await selected(on: machine)
    }

    /// Whether two installs are one toolchain: the same version and build.
    static func same(_ one: XcodeInstall, _ other: XcodeInstall) -> Bool {
        numbers(one.version) == numbers(other.version) && one.build == other.build
    }

    /// The version a workflow line names: `.some(nil)` when it names the newest or a range, nil when it names none.
    static func named(in line: String) -> String?? {
        if let input = line.firstMatch(of: /xcode-version:\s*['"]?([^'"\s#]+)/) {
            let value = String(input.1)
            return .some(value.first?.isNumber == true ? String(value.prefix { $0.isNumber || $0 == "." }) : nil)
        }
        guard line.contains("xcode-select") || line.contains("DEVELOPER_DIR"), let app = line.firstMatch(of: /Xcode[_-]?(\d+(?:\.\d+)*)[^\/\s]*\.app/) else { return nil }
        return .some(String(app.1))
    }

    /// The app a developer folder is in: `/Applications/Xcode.app` for `/Applications/Xcode.app/Contents/Developer`.
    static func app(holding developer: String) -> URL? {
        guard let range = developer.range(of: ".app/") ?? (developer.hasSuffix(".app") ? developer.range(of: ".app", options: .backwards) : nil) else { return nil }
        return URL(fileURLWithPath: String(developer[..<range.upperBound]).trimmingSuffix("/"))
    }

    /// A version's numbers, without trailing zeros: `27.2b3` and `27.2.0` are both `[27, 2]`.
    static func numbers(_ version: String) -> [Int] {
        var parts = version.trimmingCharacters(in: .whitespacesAndNewlines).prefix { $0.isNumber || $0 == "." }.split(separator: ".").compactMap { Int($0) }
        while parts.count > 1, parts.last == 0 { parts.removeLast() }
        return parts
    }

    static func isNewer(_ version: String, than other: String) -> Bool {
        let (a, b) = (numbers(version), numbers(other))
        for (x, y) in zip(a, b) where x != y { return x > y }
        return a.count > b.count
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
