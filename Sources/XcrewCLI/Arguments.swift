import Foundation

/// `--name value` options, bare `--flag`s and positional words.
public struct Arguments: Equatable {
    public private(set) var values: [String: String] = [:]
    public private(set) var flags: Set<String> = []
    public private(set) var positional: [String] = []

    /// Parses `arguments` for `command`; an option it declares in neither `valuedOptions` nor `flags` is a usage error.
    init(_ arguments: [String], for command: any Command) throws {
        var rest = arguments[...]
        while let argument = rest.popFirst() {
            guard argument.hasPrefix("--") else {
                positional.append(argument)
                continue
            }
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
