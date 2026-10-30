import Foundation

/// What the setup form offers: the containers, the chosen container's shared schemes with what each builds and tests,
/// the installed simulators, what `xcrew setup` would pick, and the config as it is. Only shared schemes count, as for
/// setup's unit-test scheme; a project with none is the skill's, which can ask `xcodebuild -list`.
public struct SetupChoices: Sendable, Equatable, Codable {
    /// What a scheme does, from its build and test entries and their targets' product types.
    public enum Role: String, Sendable, Codable {
        /// It builds an app for running.
        case app
        case unitTests = "unit-tests"
        case uiTests = "ui-tests"
    }

    public struct Scheme: Sendable, Equatable, Codable {
        public let name: String
        /// Its container, from the root.
        public let container: String
        public let roles: [Role]
        /// The app it builds for running; absent when it builds none.
        public var app: String?
        /// The project that holds `app`, as the scheme names it, by its standardized path.
        var appProject: String?

        enum CodingKeys: String, CodingKey { case name, container, roles, app }
    }

    /// An installed simulator, once per name, on the newest runtime that has it.
    public struct Simulator: Sendable, Equatable, Codable {
        public let name: String
        /// The runtime's version, as in `27.2`.
        public let runtime: String
        /// Its device type has two built-in displays, where MobileBuildMCP's `screenshot` fails; absent otherwise.
        public var twoDisplays: Bool?
    }

    /// The form's starting picks, each passed to `xcrew setup` as an option: mcs's answers where there are some, else
    /// setup's own rules applied to these schemes and simulators.
    public struct Picks: Sendable, Equatable, Codable {
        public var appScheme: String?
        public var uiScheme: String?
        public var testScheme: String?
        /// The app scheme's app's `PRODUCT_BUNDLE_IDENTIFIER`, when the project gives it literally.
        public var bundleID: String?
        public var testSimulator: String?
        /// The app's simulator, when it isn't the test simulator.
        public var appSimulator: String?
    }

    /// The config there is now.
    public struct Config: Sendable, Equatable, Codable {
        public enum Owner: String, Sendable, Codable {
            case xcrew
            /// xcrew wrote it and someone has edited it since.
            case edited
            /// Neither xcrew nor its marker: setup keeps it unless forced.
            case other
        }
        public let owner: Owner
        /// The scheme MobileBuildMCP builds with when a call names none.
        public var scheme: String?
        public var debuggerBackend: String?
    }

    public var container: String?
    public var containers: [String] = []
    public var containerProblem: String?
    public var schemes: [Scheme] = []
    public var picks = Picks()
    public var simulators: [Simulator] = []
    /// Absent when there's no config.
    public var config: Config?
    /// A linked git worktree, whose config is set up from the main checkout's; absent otherwise.
    public var worktree: Bool?

    /// The choices for `container`, a path from the root, or for none when `containerProblem` says why.
    public static func read(container: String?, containers: [String], containerProblem: String?, in project: Project, catalog: SimulatorCatalog) -> SetupChoices {
        var choices = readWithoutConfig(container: container, containers: containers, containerProblem: containerProblem, in: project, catalog: catalog)
        // The profiles xcrew wrote hold what the person chose before; setup's own rules are only for what they don't.
        guard choices.config != nil, let yaml = try? String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8) else { return choices }
        let names = ConfigRenderer.profiles(in: yaml).names
        guard !names.isEmpty else { return choices }
        func value(_ key: String, of profile: String) -> String? {
            names.contains(profile) ? ConfigRenderer.setting(key, profile: profile, in: yaml) : nil
        }
        choices.picks.appScheme = value("scheme", of: "app")
        choices.picks.uiScheme = value("scheme", of: "ui")
        choices.picks.testScheme = value("scheme", of: "unit")
        choices.picks.bundleID = value("bundleId", of: "app")
        choices.picks.testSimulator = value("simulatorName", of: "unit") ?? value("simulatorName", of: "app") ?? choices.picks.testSimulator
        let appSimulator = value("simulatorName", of: "app")
        choices.picks.appSimulator = appSimulator == choices.picks.testSimulator ? nil : appSimulator
        return choices
    }

    static func readWithoutConfig(container: String?, containers: [String], containerProblem: String?, in project: Project, catalog: SimulatorCatalog) -> SetupChoices {
        var choices = SetupChoices(container: container, containers: containers, containerProblem: containerProblem)
        choices.simulators = simulators(in: catalog)
        choices.picks.testSimulator = catalog.defaultIPhone
        if project.hasMobileBuildMCPConfig {
            let owner: Config.Owner = switch ConfigWriter.keeping(project) {
            case .keptEdited: .edited
            case .keptUnmanaged: .other
            default: .xcrew
            }
            let backend = (try? String(contentsOf: project.mobileBuildMCPConfig, encoding: .utf8)).flatMap(ConfigRenderer.debuggerBackend(in:))
            choices.config = Config(owner: owner, scheme: project.schemeToBuild, debuggerBackend: backend)
        }
        guard let container else { return choices }
        let url = project.root.appending(path: container)
        choices.schemes = schemes(of: url, from: ProjectLayout.canonical(project.root))
        // A workspace's scheme and its project's of one name are one choice, as `xcodebuild -scheme` takes them.
        var named = Set<String>()
        let apps = choices.schemes.filter { $0.roles.contains(.app) && named.insert($0.name).inserted }
        // Several schemes building apps: the one named for its app, when one is.
        let app = apps.count == 1 ? apps.first : apps.filter { $0.name == $0.app }.onlyOne
        choices.picks.appScheme = app?.name
        let ui = choices.schemes.filter { $0.roles.contains(.uiTests) }
        choices.picks.uiScheme = (app.flatMap { $0.roles.contains(.uiTests) ? $0 : nil } ?? ui.onlyOne)?.name
        if case let .scheme(scheme) = TestSchemes.choose(in: url, preferring: app?.name) { choices.picks.testScheme = scheme }
        if let target = app?.app {
            // The project the scheme builds the app from first, then any that has a target of that name.
            let all = TestSchemes.containers(from: [url]).filter { Project.isXcodeProject($0.lastPathComponent) }
            let projects = all.filter { TestSchemes.key($0) == app?.appProject } + all.filter { TestSchemes.key($0) != app?.appProject }
            choices.picks.bundleID = projects.lazy.compactMap { try? ProjectGraph.read($0) }
                .compactMap { $0.settings[ProjectGraph.bundleIdentifier]?[target]?.literal }.first
        }
        return choices
    }

    /// The shared schemes of a container and the projects its workspace lists, each with its roles.
    static func schemes(of container: URL, from root: String) -> [Scheme] {
        let containers = TestSchemes.containers(from: [container])
        let type = TestSchemes.productTypeLookup(for: containers)
        return containers.flatMap { holder -> [Scheme] in
            let base = holder.deletingLastPathComponent()
            return TestSchemes.sharedSchemes(of: holder).map { name, document in
                let references = (try? document.nodes(forXPath: "//BuildAction/BuildActionEntries/BuildActionEntry[@buildForRunning='YES']/BuildableReference")) ?? []
                let built = references.compactMap { $0 as? XMLElement }.compactMap { reference -> (target: String, project: String?)? in
                    guard let target = reference.attribute(forName: "BlueprintName")?.stringValue else { return nil }
                    let project = reference.attribute(forName: "ReferencedContainer")?.stringValue.map { TestSchemes.key(TestSchemes.resolve($0, from: base)) }
                    return type(target, project) == TestSchemes.application ? (target, project) : nil
                }
                let kinds = TestSchemes.tested(by: document, in: holder).testables.map { type($0.name, $0.project) }
                var roles: [Role] = built.isEmpty ? [] : [.app]
                if kinds.contains(TestSchemes.unitTest) { roles.append(.unitTests) }
                if kinds.contains(TestSchemes.uiTest) { roles.append(.uiTests) }
                return Scheme(name: name, container: ProjectLayout.path(ProjectLayout.canonical(holder), from: root), roles: roles, app: built.first?.target, appProject: built.first?.project ?? nil)
            }
        }
    }

    /// The installed iOS simulators, each name once with its newest runtime: iPhones first, in numeric order.
    static func simulators(in catalog: SimulatorCatalog) -> [Simulator] {
        let iOS = Dictionary(grouping: catalog.devices.filter { $0.platform == "iOS" }, by: \.name)
        return iOS.map { name, devices in
            let newest = devices.map(\.runtimeVersion).max { Version($0) < Version($1) } ?? ""
            let twoDisplays = devices.contains(where: catalog.hasTwoDisplays)
            return Simulator(name: name, runtime: newest, twoDisplays: twoDisplays ? true : nil)
        }.sorted { first, second in
            let (a, b) = (first.name.hasPrefix("iPhone"), second.name.hasPrefix("iPhone"))
            return a != b ? a : first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
    }
}

private extension Array {
    /// The element when there's exactly one.
    var onlyOne: Element? { count == 1 ? first : nil }
}
