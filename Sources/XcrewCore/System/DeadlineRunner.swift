import Foundation
import Synchronization

/// One deadline for a whole call, passed down to each command it starts: a command's limit is what's left of the
/// deadline when it's shorter than its own, and a command past the deadline isn't started. So no step's limit is set
/// apart from the call's, and each uses what the steps before it left (docs/findings.md, *Deadlines inside the CLI*).
/// The commands it cut are named, for the result to say what it left out.
public final class DeadlineRunner: CommandRunning {
    private let base: any CommandRunning
    private let deadline: Date
    private let now: @Sendable () -> Date
    private let cutCommands = Mutex<[String]>([])

    /// What the CLI keeps of its time to answer once its last command has: its whole run, start and answer, took 17 to
    /// 25 ms (*Runs that overlap another checkout's*), and this is twenty times the slowest.
    public static let answering = Duration.milliseconds(500)
    /// The time a call has when its caller names none, as when a person runs the CLI: Claude Code's own point where a
    /// command stops holding the conversation, `BASH_DEFAULT_TIMEOUT_MS`'s 120 s.
    public static let asked = Duration.seconds(120)
    /// Where the mod names the time a call has, in milliseconds.
    public static let variable = "XCREW_WITHIN_MS"

    public init(_ base: any CommandRunning, deadline: Date, now: @escaping @Sendable () -> Date) {
        self.base = base
        self.deadline = deadline
        self.now = now
    }

    /// The deadline for a call on `machine`: the time it's given (`XCREW_WITHIN_MS`), else `asked`, less `answering`.
    public static func deadline(for machine: Machine) -> Date {
        let named: Double? = machine.value(variable).flatMap(Double.init).flatMap { $0 > 0 ? $0 / 1000 : nil }
        let given: Double = named ?? seconds(asked)
        return machine.now().addingTimeInterval(given - seconds(answering))
    }

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    public func run(_ argv: [String], stdin: Data?, timeout: Duration) async -> CommandResult {
        let left = deadline.timeIntervalSince(now())
        guard left > 0 else {
            note(argv)
            return .timedOut
        }
        let cutShort = Duration.seconds(left) < timeout
        let answer = await base.run(argv, stdin: stdin, timeout: cutShort ? .seconds(left) : timeout)
        if cutShort, answer == .timedOut { note(argv) }
        return answer
    }

    public func which(_ name: String) -> String? { base.which(name) }

    /// The programs the deadline cut, in the order cut, each once: `xcrun`'s tool by its own name.
    public var cut: [String] { cutCommands.withLock { $0 } }

    private func note(_ argv: [String]) {
        let program = argv.first == "xcrun" ? argv.dropFirst().first : argv.first
        guard let name = program.map({ URL(fileURLWithPath: $0).lastPathComponent }) else { return }
        cutCommands.withLock { if !$0.contains(name) { $0.append(name) } }
    }
}
