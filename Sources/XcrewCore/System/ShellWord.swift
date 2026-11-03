import Foundation

/// A path or value as one word of a shell command xcrew hands Claude or the person.
public enum ShellWord {
    /// In single quotes, each one inside it closed, escaped and reopened.
    public static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// As it is when it holds only letters, digits and `/._-`, which a shell reads as one word; quoted otherwise.
    public static func word(_ text: String) -> String {
        text.allSatisfy { $0.isLetter || $0.isNumber || "/._-".contains($0) } ? text : quoted(text)
    }

    /// The value a word from `quoted` stands for; any other word as it is.
    public static func unquoted(_ word: String) -> String {
        guard word.count > 1, word.hasPrefix("'"), word.hasSuffix("'") else { return word }
        return word.dropFirst().dropLast().replacingOccurrences(of: #"'\''"#, with: "'")
    }
}
