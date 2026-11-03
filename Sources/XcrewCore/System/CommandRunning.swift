import Foundation

public struct CommandResult: Sendable, Equatable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String = "", stderr: String = "") {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool { status == 0 }
    public static let notFound = CommandResult(status: 127, stderr: "not found")
    public static let timedOut = CommandResult(status: 124, stderr: "timed out")
}

/// Runs external programs. Everything in xcrew that touches the system goes through this, so
/// tests substitute a fake and no check needs a real Mac setup to be tested.
public protocol CommandRunning: Sendable {
    func run(_ argv: [String], stdin: Data?, timeout: Duration) async -> CommandResult
    /// The executable's absolute path, or nil when it isn't installed.
    func which(_ name: String) -> String?
}

extension CommandRunning {
    public func run(_ argv: String..., stdin: Data? = nil, timeout: Duration = .seconds(30)) async -> CommandResult {
        await run(argv, stdin: stdin, timeout: timeout)
    }
}
