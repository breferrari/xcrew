import Foundation

/// Xcode's scheme selection as MobileBuildMCP 2.7.1 takes it (docs/findings.md, *Xcode's scheme selection*): only when
/// Xcode hosts its server, read from the workspace's `xcuserstate` at its start and written over the active profile's
/// scheme, then followed as it changes unless the config sets `disableXcodeAutoSync`.
public struct XcodeSelection: Sendable, Equatable {
    /// The `xcuserstate` file MobileBuildMCP reads and watches.
    public let state: URL
    /// The scheme selected in it; nil when it names none or can't be read.
    public let scheme: String?
    /// Whether MobileBuildMCP follows the file after its start.
    public let follows: Bool
    /// The config's active profile, whose scheme the selection at the server's start is written over; with none active,
    /// MobileBuildMCP's name for its global defaults.
    public let activeProfile: String

    /// For the MobileBuildMCP server serving `project` in the session that runs this process: whether Xcode started it,
    /// and then its selection, nil when no `xcuserstate` is found. Nil when no such server runs yet.
    public static func read(for project: Project, machine: Machine) async -> (hostsServer: Bool, selection: XcodeSelection?)? {
        let list = await ProcessList.load(using: machine.runner)
        guard let (server, _) = await list.mobileBuildMCPServer(serving: project, forSessionOf: machine.processID, using: machine.runner) else { return nil }
        guard list.runsUnderXcode(server.id) else { return (false, nil) }
        return (true, await selection(for: project, machine: machine))
    }

    static func selection(for project: Project, machine: Machine) async -> XcodeSelection? {
        let whoami = await machine.runner.run("whoami")
        let user = whoami.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard whoami.succeeded, !user.isEmpty else { return nil }
        let yaml = (try? String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8)) ?? ""
        let configured = (ConfigRenderer.setting("workspacePath", in: yaml) ?? ConfigRenderer.setting("projectPath", in: yaml))
            .map { URL(fileURLWithPath: ConfigRenderer.resolved($0, root: project.root, home: machine.home)) }
        guard let state = stateFile(in: project, configured: configured, user: user) else { return nil }
        return XcodeSelection(
            state: state, scheme: scheme(inStateAt: state), follows: !ConfigRenderer.disablesXcodeAutoSync(in: yaml),
            activeProfile: ConfigRenderer.profiles(in: yaml).active ?? ConfigRenderer.globalProfile
        )
    }

    /// The scheme selected in an `xcuserstate` file, read the way MobileBuildMCP's parser reads it; nil when the file
    /// isn't there, isn't a keyed archive, or names none.
    public static func scheme(inStateAt url: URL) -> String? {
        (try? Data(contentsOf: url)).flatMap(scheme(in:))
    }

    /// The scheme selected in an `xcuserstate` file's contents, by `parseXcuserstate`: the dictionary among `$objects`
    /// whose keys include `ActiveScheme`, that key's value, and its `IDENameString`.
    static func scheme(in data: Data) -> String? {
        guard case let .dictionary(root)? = BinaryPropertyList.read(data), root["$archiver"] == .string("NSKeyedArchiver"),
              case let .array(objects)? = root["$objects"],
              let activeScheme = objects.firstIndex(of: .string("ActiveScheme")),
              let nameString = objects.firstIndex(of: .string("IDENameString")) else { return nil }
        func value(of key: Int, in dictionary: [String: BinaryPropertyList]) -> BinaryPropertyList? {
            guard case let .array(keys)? = dictionary["NS.keys"], case let .array(values)? = dictionary["NS.objects"],
                  let position = keys.firstIndex(of: .uid(key)), position < values.count else { return nil }
            guard case let .uid(index) = values[position] else { return values[position] }
            return objects.indices.contains(index) ? objects[index] : nil
        }
        let parent = objects.lazy.compactMap { object -> [String: BinaryPropertyList]? in
            guard case let .dictionary(dictionary) = object, case let .array(keys)? = dictionary["NS.keys"], keys.contains(.uid(activeScheme)) else { return nil }
            return dictionary
        }.first
        guard let parent, case let .dictionary(selected)? = value(of: activeScheme, in: parent),
              case let .string(scheme)? = value(of: nameString, in: selected) else { return nil }
        return scheme
    }

    /// The `xcuserstate` MobileBuildMCP reads for `user`: the one beside the configured container when it's there, else
    /// the newest among the workspaces and projects up to six folders below the root.
    static func stateFile(in project: Project, configured: URL?, user: String) -> URL? {
        func state(of container: URL) -> URL {
            let workspace = Project.isXcodeWorkspace(container.lastPathComponent) ? container : container.appending(path: "project.xcworkspace")
            return workspace.appending(path: "xcuserdata/\(user).xcuserdatad/UserInterfaceState.xcuserstate").standardizedFileURL
        }
        let files = FileManager.default
        if let configured, files.fileExists(atPath: state(of: configured).path) { return state(of: configured) }
        // `find <root> -maxdepth 6 ( -name *.xcworkspace -o -name *.xcodeproj ) -type d`; the server's folder is the root,
        // so no folder above it is searched.
        guard let walk = files.enumerator(at: project.root, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        var containers: [URL] = []
        while let url = walk.nextObject() as? URL {
            if walk.level > 6 {
                walk.skipDescendants()
                continue
            }
            guard Project.isXcodeContainer(url.lastPathComponent), (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  !url.path.contains(".xcodeproj/project.xcworkspace") else { continue }
            containers.append(url)
        }
        // Workspaces first, then the newest file to the second, as `stat -f %m` gives it; `max` keeps the first of equals.
        let ordered = containers.filter { Project.isXcodeWorkspace($0.lastPathComponent) } + containers.filter { !Project.isXcodeWorkspace($0.lastPathComponent) }
        let found = ordered.compactMap { container -> (file: URL, modified: TimeInterval)? in
            let file = state(of: container)
            guard let modified = (try? files.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date else { return nil }
            return (file, modified.timeIntervalSince1970.rounded(.down))
        }
        return found.max { $0.modified < $1.modified }?.file
    }
}
