import Foundation

/// With this Xcode default on, any unsigned process on the Mac may drive Xcode's tools. xcrew runs either way, so it's
/// said once, by the setup run that looks at the Mac, not by the doctor.
public enum UnsignedAgents {
    /// The line setup prints when Xcode accepts unsigned agents; nothing when it refuses them or the default isn't set.
    public static func note(using runner: any CommandRunning) async -> String? {
        let value = await runner.run("defaults", "read", "com.apple.dt.Xcode", "IDEAllowUnauthenticatedAgents").stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return value == "1" ? accepted : nil
    }

    /// The line `note` gives when Xcode accepts unsigned agents.
    static let accepted = "xcrew: Xcode accepts unsigned agents, so any unsigned process on this Mac may drive Xcode's tools: defaults write com.apple.dt.Xcode IDEAllowUnauthenticatedAgents -bool NO"
}
