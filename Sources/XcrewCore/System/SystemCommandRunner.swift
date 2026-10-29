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
                try? await Task.sleep(until: deadline, clock: .continuous)
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
            group.addTask {
                await stdout.ended()
                await stderr.ended()
            }
            group.addTask {
                try? await Task.sleep(until: deadline, clock: .continuous)
                stdout.stop()
                stderr.stop()
            }
            await group.next()
            group.cancelAll()
        }
        return (stdout.text, stderr.text)
    }
}

/// A pipe's output as it arrives, until end of file or until the runner stops waiting for it.
final class Drain: Sendable {
    private struct State {
        var data = Data()
        var isEnded = false
        var waiter: CheckedContinuation<Void, Never>?
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

    /// Stops reading; reaching end of file and giving up on the pipe both end here.
    func stop() {
        handle.readabilityHandler = nil
        let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.isEnded = true
            let waiter = state.waiter
            state.waiter = nil
            return waiter
        }
        waiter?.resume()
    }

    /// Returns once reading has stopped.
    func ended() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isEnded = state.withLock { state -> Bool in
                if !state.isEnded { state.waiter = continuation }
                return state.isEnded
            }
            if isEnded { continuation.resume() }
        }
    }

    /// What has arrived so far.
    var text: String {
        String(decoding: state.withLock { $0.data }, as: UTF8.self)
    }
}
