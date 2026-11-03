import Foundation

/// Runs real processes to their end and awaits them without blocking a thread. A program that isn't found reads as
/// status 127, as a shell reports it.
public struct SystemCommandRunner: CommandRunning {
    let searchPath: [String]

    /// Homebrew's prefixes are appended because mcs and Claude Code can start xcrew without a
    /// login shell.
    public init(path: String? = ProcessInfo.processInfo.environment["PATH"]) {
        let inherited = (path ?? "").split(separator: ":").map(String.init)
        searchPath = inherited + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
    }

    public func which(_ name: String) -> String? {
        searchPath.lazy.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// How long the pipes may stay open once the program has ended: a background child that outlives it can hold them for
    /// as long as it lives (docs/findings.md, *Stopping a program*), and the program's last output can arrive just after
    /// its exit. A cap on that child, not a measured time: the program's own output is in the pipe when it exits.
    static let grace = Duration.seconds(1)

    public func run(_ argv: [String], stdin: Data?) async -> CommandResult {
        guard let name = argv.first, let executable = name.hasPrefix("/") ? name : which(name) else { return .notFound }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(argv.dropFirst())
        let output = Pipe(), errors = Pipe(), input = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = input

        let exit = AsyncStream<Int32> { continuation in
            process.terminationHandler = { continuation.yield($0.terminationStatus); continuation.finish() }
        }
        do { try process.run() } catch { return CommandResult(status: 127, stderr: "\(error)") }

        // Both pipes drain while the child runs, so a chatty child can't block on a full pipe.
        let stdout = Drain(output.fileHandleForReading), stderr = Drain(errors.fileHandleForReading)
        if let stdin { try? input.fileHandleForWriting.write(contentsOf: stdin) }
        try? input.fileHandleForWriting.close()

        // A task cancelled meanwhile stops the program and the children it started, as its answer is no longer wanted:
        // the program leads a process group of its own, and the group is signalled (docs/findings.md, *Stopping a
        // program*).
        let group = -process.processIdentifier
        let status = await withTaskCancellationHandler {
            await exit.first { _ in true }
        } onCancel: {
            kill(group, SIGTERM)
        }
        let (out, err) = await Self.collect(stdout, stderr, until: ContinuousClock.now + Self.grace)
        guard let status else { return .cancelled }
        return CommandResult(status: status, stdout: out, stderr: err)
    }

    /// Both pipes' text, read to end of file or until `deadline`, whichever comes first.
    static func collect(_ stdout: Drain, _ stderr: Drain, until deadline: ContinuousClock.Instant) async -> (String, String) {
        await stdout.ended(by: deadline)
        await stderr.ended(by: deadline)
        return (stdout.text, stderr.text)
    }
}
