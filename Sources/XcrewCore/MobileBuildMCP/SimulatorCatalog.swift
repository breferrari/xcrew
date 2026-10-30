import Foundation

/// The simulators installed on this Mac, read from `simctl`, so xcrew's defaults follow whatever
/// Xcode ships instead of a device name that ages.
public struct SimulatorCatalog: Sendable {
    public struct Device: Sendable, Equatable {
        public let name: String
        /// The runtime's version, as in `26.5`.
        public let runtimeVersion: String
        public let platform: String
        public var udid: String? = nil
        /// Its device type, as in `com.apple.CoreSimulator.SimDeviceType.iPhone-17`.
        public var deviceType: String? = nil
        /// `Booted`, `Shutdown`, or another of `simctl`'s states.
        public var state: String? = nil

        var isIPhone: Bool { platform == "iOS" && name.hasPrefix("iPhone") }
    }

    public let devices: [Device]
    /// Device types with more than one built-in display, where MobileBuildMCP's `screenshot` fails.
    public var multiDisplayTypes: Set<String> = []

    public init(devices: [Device]) {
        self.devices = devices
    }

    /// The simulators installed. Choosing a default also reads each runtime's version and which iPhones have two
    /// displays (docs/findings.md, *The simulator setup picks*); `displaysOf` reads the displays of those simulators only.
    public static func load(using runner: any CommandRunning, choosingADefault: Bool = false, displaysOf names: Set<String> = []) async -> SimulatorCatalog {
        async let devices = runner.run("xcrun", "simctl", "list", "devices", "available", "--json")
        let runtimes = choosingADefault ? await runner.run("xcrun", "simctl", "list", "runtimes", "--json").stdout : nil
        var catalog = SimulatorCatalog(json: Data(await devices.stdout.utf8), runtimes: runtimes.map { Data($0.utf8) })
        let wanted = Set(catalog.devices.filter { choosingADefault ? $0.isIPhone : names.contains($0.name) }.compactMap(\.deviceType))
        guard !wanted.isEmpty else { return catalog }
        let types = await runner.run("xcrun", "simctl", "list", "devicetypes", "--json")
        let bundles = ((try? JSONDecoder().decode(DeviceTypes.self, from: Data(types.stdout.utf8)))?.devicetypes ?? [])
            .compactMap { type in type.identifier.flatMap { id in type.bundlePath.map { (id, $0) } } }
            .filter { wanted.contains($0.0) }
        catalog.multiDisplayTypes = await withTaskGroup(of: String?.self) { group in
            for (identifier, bundle) in bundles {
                group.addTask {
                    let read = await runner.run("plutil", "-extract", "capabilities.displays", "json", "-o", "-", "\(bundle)/Contents/Resources/capabilities.plist")
                    let displays = (try? JSONDecoder().decode([Display].self, from: Data(read.stdout.utf8))) ?? []
                    return displays.filter { $0.powerState == 1 }.count > 1 ? identifier : nil
                }
            }
            return await group.reduce(into: Set<String>()) { found, identifier in
                if let identifier { found.insert(identifier) }
            }
        }
        return catalog
    }

    /// Entries are optional throughout, so one odd entry doesn't lose the whole list.
    struct DeviceTypes: Decodable {
        struct DeviceType: Decodable {
            let identifier: String?
            let bundlePath: String?
        }
        let devicetypes: [DeviceType]
    }

    /// A display in a device type's profile: the built-in ones are powered on by default.
    struct Display: Decodable {
        let powerState: Int?
    }

    struct Runtimes: Decodable {
        struct Runtime: Decodable {
            struct DeviceType: Decodable {
                let name: String?
                let identifier: String?
            }
            let identifier: String?
            let version: String?
            let platform: String?
            let isAvailable: Bool?
            let supportedDeviceTypes: [DeviceType]?
        }
        let runtimes: [Runtime]
    }

    /// The command that creates a simulator named `name`, from `simctl list runtimes --json`: the device type of that
    /// name on the newest available runtime that supports it. Nil when no installed runtime does.
    public static func createCommand(for name: String, runtimes: Data) -> String? {
        let listed = (try? JSONDecoder().decode(Runtimes.self, from: runtimes))?.runtimes ?? []
        let candidates = listed.compactMap { runtime -> (version: Version, runtime: String, type: String)? in
            guard runtime.isAvailable != false, let id = runtime.identifier,
                  let type = runtime.supportedDeviceTypes?.first(where: { $0.name == name })?.identifier else { return nil }
            return (Version(runtime.version ?? ""), id, type)
        }
        return candidates.max { $0.version < $1.version }.map { "xcrun simctl create \"\(name)\" \($0.type) \($0.runtime)" }
    }

    /// Parses `simctl list devices --json`, with each runtime's version and platform from `simctl list runtimes
    /// --json` when given, else from the identifier's leading numbers.
    public init(json: Data, runtimes: Data? = nil) {
        let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
        let byRuntime = root?["devices"] as? [String: [[String: Any]]] ?? [:]
        let listed = runtimes.flatMap { try? JSONDecoder().decode(Runtimes.self, from: $0) }?.runtimes ?? []
        let known = listed.reduce(into: [String: (version: String, platform: String)]()) { known, runtime in
            if let id = runtime.identifier, let version = runtime.version, let platform = runtime.platform { known[id] = (version, platform) }
        }
        // In identifier order, so two runtimes of one version always tie the same way: the plain one first.
        devices = byRuntime.sorted { $0.key < $1.key }.flatMap { runtime, entries -> [Device] in
            let pieces = (runtime.split(separator: ".").last.map(String.init) ?? "").split(separator: "-").map(String.init)
            guard let platform = known[runtime]?.platform ?? pieces.first else { return [] }
            let version = known[runtime]?.version ?? pieces.dropFirst().prefix { Int($0) != nil }.joined(separator: ".")
            return entries.compactMap { entry in
                guard entry["isAvailable"] as? Bool ?? true, let name = entry["name"] as? String else { return nil }
                return Device(name: name, runtimeVersion: version, platform: platform, udid: entry["udid"] as? String, deviceType: entry["deviceTypeIdentifier"] as? String, state: entry["state"] as? String)
            }
        }
    }

    /// The simulators booted or booting now, or none when `simctl` doesn't answer within `timeout`. Its `booted` filter matches each
    /// device's description, so a device's own `state` decides.
    public static func booted(using runner: any CommandRunning, timeout: Duration) async -> [Device] {
        let listed = await runner.run("xcrun", "simctl", "list", "devices", "booted", "--json", timeout: timeout)
        return SimulatorCatalog(json: Data(listed.stdout.utf8)).devices.filter { ["Booted", "Booting"].contains($0.state) }
    }

    public var names: Set<String> { Set(devices.map(\.name)) }

    /// The installed iPhones' names, each once, in numeric order.
    public var iPhoneNames: [String] { Array(Set(devices.filter(\.isIPhone).map(\.name))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }

    /// The UDID of the simulator called `name`, on the newest runtime that has one, as `defaultIPhone` picks runtimes.
    public func udid(of name: String) -> String? {
        devices.filter { $0.name == name && $0.udid != nil }.max { Version($0.runtimeVersion) < Version($1.runtimeVersion) }?.udid
    }

    /// The newest plain iPhone ("iPhone 17", not "iPhone 17 Pro Max") on the newest iOS version,
    /// else any iPhone there, never one with two displays.
    public var defaultIPhone: String? {
        let iOS = devices.filter { $0.isIPhone && !($0.deviceType.map(multiDisplayTypes.contains) ?? false) }
        guard let newest = iOS.map({ Version($0.runtimeVersion) }).max() else { return nil }
        let onNewest = iOS.filter { Version($0.runtimeVersion) == newest }.map(\.name)
        let plain = onNewest.filter { $0.range(of: #"^iPhone \d+$"#, options: .regularExpression) != nil }
        return plain.max { Version($0) < Version($1) } ?? onNewest.sorted().first
    }
}
