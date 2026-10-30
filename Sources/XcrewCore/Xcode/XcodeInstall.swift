import Foundation

/// An installed Xcode: where it is, its version and its build.
public struct XcodeInstall: Sendable, Equatable {
    public let path: String
    public let version: String
    public let build: String

    /// `Xcode 26.4`, as the doctor and `xcrew xcode` name it.
    public var label: String { "Xcode \(version)" }

    /// Whether it shows simulators in DeviceHub and has no Simulator.app, as from Xcode 27, read from the bundle.
    var hasDeviceHubOnly: Bool {
        FileManager.default.fileExists(atPath: "\(path)/Contents/Applications/DeviceHub.app") && !hasSimulatorApp
    }

    /// Whether it ships Simulator.app, which `open -a Simulator` opens.
    var hasSimulatorApp: Bool {
        FileManager.default.fileExists(atPath: "\(developerFolder)/Applications/Simulator.app")
    }

    /// The folder `DEVELOPER_DIR` names for it.
    public var developerFolder: String { "\(path)/Contents/Developer" }

    /// Whether it's the same toolchain as `other`: the same version and build, wherever each copy is.
    public func isSameToolchain(as other: XcodeInstall) -> Bool {
        Version(version) == Version(other.version) && build == other.build
    }
}
