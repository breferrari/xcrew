import Foundation

/// `--name value` options, bare `--flag`s and positional words.
public struct Arguments: Equatable {
    public private(set) var values: [String: String] = [:]
    public private(set) var flags: Set<String> = []
    public private(set) var positional: [String] = []
    /// Whether `--help` or `-h` stood where an option could; the command's usage is printed instead of running it.
    public private(set) var wantsHelp = false

    /// Parses `arguments` for `command`. An option it doesn't declare, or a word when it takes none, is a usage error.
    public init(_ arguments: [String], for command: any Command) throws {
        var rest = arguments[...]
        while let argument = rest.popFirst() {
            if CLI.helpOptions.contains(argument) {
                wantsHelp = true
                return
            }
            guard argument.hasPrefix("-"), argument.count > 1 else {
                guard command.takesWords else { throw UsageError(description: "unexpected '\(argument)' (xcrew \(command.name) --help)") }
                positional.append(argument)
                continue
            }
            guard argument.hasPrefix("--") else { throw UsageError(description: "unknown option '\(argument)' (xcrew \(command.name) --help)") }
            let name = String(argument.dropFirst(2))
            if command.valuedOptions.contains(name) {
                guard let value = rest.popFirst() else { throw UsageError(description: "--\(name) needs a value") }
                values[name] = value
            } else if command.flags.contains(name) {
                flags.insert(name)
            } else {
                throw UsageError(description: "unknown option '--\(name)' (xcrew \(command.name) --help)")
            }
        }
    }

    public subscript(name: String) -> String? { values[name] }
    public func has(_ flag: String) -> Bool { flags.contains(flag) }
}
