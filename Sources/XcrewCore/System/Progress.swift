/// A line the CLI writes to standard error while it waits on something, for the person: the mod shows it, the
/// `xcrew progress: ` before it telling it from a reason the command failed.
public enum Progress {
    public static let prefix = "xcrew progress: "

    /// The line as the CLI writes it.
    public static func line(_ text: String) -> String { "\(prefix)\(text)\n" }
}
