import Foundation
import XcrewCore

/// One `xcrew <name>` subcommand. Add one by writing a type in this folder and listing it in
/// `CLI.commands`.
public protocol Command: Sendable {
    var name: String { get }
    /// One usage line per form, shown by `xcrew help`.
    var usage: [String] { get }
    /// Option names that take a value.
    var valuedOptions: Set<String> { get }
    /// Option names that take no value. Any `--name` in neither set is a usage error.
    var flags: Set<String> { get }
    /// Whether it takes words besides its options, such as names.
    var takesWords: Bool { get }
    /// Returns the process exit status.
    func run(_ invocation: Invocation) async throws -> Int32
}

extension Command {
    public var valuedOptions: Set<String> { [] }
    public var flags: Set<String> { [] }
    public var takesWords: Bool { false }
}

/// Everything a command reads and writes, so a test can run it without a process.
public struct Invocation {
    public let arguments: Arguments
    public let context: CheckContext
    public let standardInput: () -> Data
    public let print: (String) -> Void

    public init(arguments: Arguments, context: CheckContext, standardInput: @escaping () -> Data, print: @escaping (String) -> Void) {
        self.arguments = arguments
        self.context = context
        self.standardInput = standardInput
        self.print = print
    }
}

public struct UsageError: Error, CustomStringConvertible, Equatable {
    public let description: String
}
