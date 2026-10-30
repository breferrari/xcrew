import Foundation

/// Why a build failed when the cause is the Mac, not the code: the cause, read from the errors and confirmed on the
/// Mac, and the fix, named and never run. Nothing when no cause matches, since a wrong cause sends Claude down a wrong
/// path.
public enum Why {
    static let prefix = "xcrew: this build failed because of the Mac, not the code: "

    static let causes: [any MachineCause] = [
        CorruptModuleCache(),
        MissingSimulator(),
        LockedBuildDatabase(),
    ]

    /// For a failed run's result: its errors, and the build log it names for what they leave out.
    public static func note(for output: ToolOutput, home: String, project: Project, runner: any CommandRunning) async -> String? {
        await note(for: FailureEvidence(errors: output.reportedErrors, project: project, runner: runner) { output.buildLog(home: home) })
    }

    /// The first cause the failure shows, with its fix.
    public static func note(for failure: FailureEvidence) async -> String? {
        for cause in causes {
            if let explanation = await cause.explanation(of: failure) { return prefix + explanation }
        }
        return nil
    }
}
