import Foundation
import XcrewCore

public enum CLI {
    public static let commands: [any Command] = [
        SetupCommand(),
        DoctorCommand(),
        AffectedCommand(),
        GraphCommand(),
        ConcurrencyCommand(),
        ReportCommand(),
        NoteCommand(),
        SessionCommand(),
        CardCommand(),
        EvidenceCommand(),
        PhaseCommand(),
        RunsCommand(),
        ProjectCommand(),
        XcodeSkillsCommand(),
        XcodeCommand(),
        WhyCommand(),
        SpaceCommand(),
        LookCommand(),
        HookCommand(),
    ]

    /// Runs `xcrew <argv>` and returns the exit status; errors go to `printError`.
    public static func run(
        _ argv: [String],
        context: CheckContext,
        standardInput: @escaping () async -> Data = { Data() },
        print: @escaping (String) -> Void = { Swift.print($0) },
        printError: (String) -> Void = { FileHandle.standardError.write(Data("xcrew: \($0)\n".utf8)) }
    ) async -> Int32 {
        guard let name = argv.first, name != "help", !helpOptions.contains(name) else {
            print(usage)
            return 0
        }
        if ["--version", "version"].contains(name) {
            print("xcrew \(XcrewVersion.current)")
            return 0
        }
        guard let command = commands.first(where: { $0.name == name }) else {
            printError("unknown command '\(name)' (xcrew help)")
            return 64
        }
        do {
            let arguments = try Arguments(Array(argv.dropFirst()), for: command)
            if arguments.wantsHelp {
                (["usage:"] + command.usage.map { "  \($0)" }).forEach(print)
                return 0
            }
            return try await command.run(Invocation(arguments: arguments, context: context, standardInput: standardInput, print: print))
        } catch let error as UsageError {
            printError(error.description)
            return 64
        } catch {
            printError(error.localizedDescription)
            return 1
        }
    }

    /// What asks for usage: after a command, that command's; alone, every command's.
    static let helpOptions: Set = ["--help", "-h"]

    public static var usage: String {
        (["usage: xcrew <command> [options]", ""]
            + commands.flatMap(\.usage).map { "  \($0)" }
            + ["  --version              print the version"]
            + ["", "The project is MCS_PROJECT_PATH, else CLAUDE_PROJECT_DIR, else the working directory."])
            .joined(separator: "\n")
    }
}
