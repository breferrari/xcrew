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
    }

    public let devices: [Device]

    public init(devices: [Device]) {
        self.devices = devices
    }

    public static func load(using runner: any CommandRunning) async -> SimulatorCatalog {
        let output = await runner.run("xcrun", "simctl", "list", "devices", "available", "--json")
        return SimulatorCatalog(json: Data(output.stdout.utf8))
    }

    /// Parses `simctl list devices --json`, whose runtime keys read like
    /// `com.apple.CoreSimulator.SimRuntime.iOS-26-5`.
    public init(json: Data) {
        let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
        let byRuntime = root?["devices"] as? [String: [[String: Any]]] ?? [:]
        devices = byRuntime.flatMap { runtime, entries -> [Device] in
            let tail = runtime.split(separator: ".").last.map(String.init) ?? ""
            let pieces = tail.split(separator: "-")
            guard let platform = pieces.first else { return [] }
            let version = pieces.dropFirst().joined(separator: ".")
            return entries.compactMap { entry in
                guard entry["isAvailable"] as? Bool ?? true, let name = entry["name"] as? String else { return nil }
                return Device(name: name, runtimeVersion: version, platform: String(platform), udid: entry["udid"] as? String)
            }
        }
    }

    public var names: Set<String> { Set(devices.map(\.name)) }

    /// The UDID of the simulator called `name`, on the newest runtime that has one, as `defaultIPhone` picks runtimes.
    public func udid(of name: String) -> String? {
        devices.filter { $0.name == name && $0.udid != nil }.max { Version($0.runtimeVersion) < Version($1.runtimeVersion) }?.udid
    }

    /// The newest plain iPhone ("iPhone 17", not "iPhone 17 Pro Max") on the newest iOS runtime,
    /// else any iPhone there.
    public var defaultIPhone: String? {
        let iOS = devices.filter { $0.platform == "iOS" && $0.name.hasPrefix("iPhone") }
        guard let newest = iOS.map({ Version($0.runtimeVersion) }).max() else { return nil }
        let onNewest = iOS.filter { Version($0.runtimeVersion) == newest }.map(\.name)
        let plain = onNewest.filter { $0.range(of: #"^iPhone \d+$"#, options: .regularExpression) != nil }
        return plain.max { Version($0) < Version($1) } ?? onNewest.sorted().first
    }
}
