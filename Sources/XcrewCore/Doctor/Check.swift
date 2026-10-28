import Foundation

/// A check's outcome. The raw values are mcs's exit codes for a check script.
public enum CheckStatus: Int32, Sendable, Comparable {
    case pass = 0, fail = 1, warn = 2, skip = 3

    /// How bad the outcome is: a skip is as harmless as a pass.
    var severity: Int {
        switch self {
        case .pass, .skip: 0
        case .warn: 1
        case .fail: 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.severity < rhs.severity }

    public var tag: String {
        switch self {
        case .pass: "ok"
        case .fail: "FAIL"
        case .warn: "warn"
        case .skip: "skip"
        }
    }
}

public struct CheckResult: Sendable, Equatable {
    public let status: CheckStatus
    /// One line: what was found, and for a failure or warning, the command that fixes it.
    public let message: String

    public init(status: CheckStatus, message: String) {
        self.status = status
        self.message = message
    }

    public static func pass(_ message: String) -> Self { .init(status: .pass, message: message) }
    public static func fail(_ message: String) -> Self { .init(status: .fail, message: message) }
    public static func warn(_ message: String) -> Self { .init(status: .warn, message: message) }
    public static func skip(_ message: String) -> Self { .init(status: .skip, message: message) }
}

/// What a check may look at.
public struct CheckContext: Sendable {
    public let project: Project
    public let machine: Machine

    public init(project: Project, machine: Machine) {
        self.project = project
        self.machine = machine
    }

    public var runner: any CommandRunning { machine.runner }
}

/// One health check. To add one, write a type in `Doctor/Checks/` and list it in
/// `Doctor.checks`; `xcrew doctor` and the mcs techpack both read that list.
public protocol Check: Sendable {
    /// `<area>/<name>`. Stable: mcs and scripts address a check by it.
    var id: String { get }
    var title: String { get }
    /// Whether it calls out to the network, which the session-start `doctor --problems` leaves out.
    var reachesNetwork: Bool { get }
    func run(_ context: CheckContext) async -> CheckResult
}

extension Check {
    public var reachesNetwork: Bool { false }
}
