import Foundation
import Synchronization

/// Runs real processes and awaits them without blocking a thread. A program that isn't found
/// reads as status 127 and one that outlives its timeout as 124, as a shell reports them.
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

    /// How long the pipes may stay open once the program has ended: a background child it started can hold them
    /// for as long as it lives.
    static let grace = Duration.seconds(1)

    public func run(_ argv: [String], stdin: Data?, timeout: Duration) async -> CommandResult {
        let deadline = ContinuousClock.now + timeout
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

        let status = await withTaskGroup(of: Int32?.self) { group in
            group.addTask { await exit.first { _ in true } }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let status else {
            process.terminate()
            _ = await Self.collect(stdout, stderr, until: .now + Self.grace)
            return .timedOut
        }
        // The program's own output is in by now; what's still open belongs to a child it left running.
        let (out, err) = await Self.collect(stdout, stderr, until: max(deadline, .now + Self.grace))
        return CommandResult(status: status, stdout: out, stderr: err)
    }

    /// Both pipes' text, read to end of file or until `deadline`, whichever comes first.
    static func collect(_ stdout: Drain, _ stderr: Drain, until deadline: ContinuousClock.Instant) async -> (String, String) {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = await (stdout.text, stderr.text) }
            group.addTask {
                try? await Task.sleep(until: deadline, clock: .continuous)
                stdout.stop()
                stderr.stop()
            }
            await group.next()
            group.cancelAll()
        }
        return (await stdout.text, await stderr.text)
    }
}

/// A pipe's output as it arrives, until end of file or until the runner stops waiting for it.
final class Drain: Sendable {
    private struct State {
        var data = Data()
        var isEnded = false
        var waiters: [CheckedContinuation<Data, Never>] = []
    }

    private let handle: FileHandle
    private let state = Mutex(State())

    init(_ handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { stop() } else { state.withLock { $0.data.append(chunk) } }
        }
    }

    /// Stops reading and hands out what has arrived; reading at end of file and giving up both end here.
    func stop() {
        handle.readabilityHandler = nil
        let (waiters, data) = state.withLock { state -> ([CheckedContinuation<Data, Never>], Data) in
            guard !state.isEnded else { return ([], state.data) }
            state.isEnded = true
            defer { state.waiters = [] }
            return (state.waiters, state.data)
        }
        waiters.forEach { $0.resume(returning: data) }
    }

    /// What arrived, once reading has stopped.
    var text: String {
        get async {
            let data = await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
                let ended = state.withLock { state -> Data? in
                    if state.isEnded { return state.data }
                    state.waiters.append(continuation)
                    return nil
                }
                if let ended { continuation.resume(returning: ended) }
            }
            return String(decoding: data, as: UTF8.self)
        }
    }
}
