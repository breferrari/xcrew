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

    /// What the CLI keeps of its time to answer once its last command has: `SystemCommandRunner.grace`, 1 s, for which a
    /// command the deadline stopped still has its output waited, then 0.5 s for the CLI's own answer, whose whole run,
    /// start and answer, took 17 to 25 ms (*Runs that overlap another checkout's*). The grace is the runner's own, not a
    /// mod hook's `.catch` grace, and neither its 1 s nor the 0.5 s, twenty times the slowest run, has a measured basis.
    public static let answering = Duration.milliseconds(1_500)
    /// The time a call has when its caller names none, as when a person runs the CLI: Claude Code's own point where a
    /// command stops holding the conversation, `BASH_DEFAULT_TIMEOUT_MS`'s 120 s.
    public static let asked = Duration.seconds(120)
    /// The limit of a command with none of its own, as a result bundle's reads: the call's deadline ends it first, and
    /// a runner with no deadline, as a test's, stops it where a call asked for would.
    public static let untimed = asked
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
        duration / .seconds(1)
    }

    public func run(_ argv: [String], stdin: Data?, timeout: Duration) async -> CommandResult {
        let left = deadline.timeIntervalSince(now())
        guard left > 0 else {
            note(argv)
            return .timedOut
        }
        let limited = Duration.seconds(left) < timeout
        let answer = await base.run(argv, stdin: stdin, timeout: limited ? .seconds(left) : timeout)
        // Cut only when the deadline stopped it: one on its own limit, or that timed out with time left, was cancelled,
        // however long its output held it after.
        if answer == .timedOut, limited, now() >= deadline { note(argv) }
        return answer
    }

    public func which(_ name: String) -> String? { base.which(name) }

    /// The programs the deadline cut, in the order cut, each once: `xcrun`'s tool by its own name.
    public var cut: [String] { cutCommands.withLock { $0 } }

    /// What a call's answer says when the deadline cut a command: which programs didn't answer in time, and the notes
    /// their answers add that are left out of `answer`, "this result" or "this block"; nil when nothing was cut. A fact,
    /// to read beside it, after `leadIn` when one is given, as a report's note starts "xcrew: ".
    public static func leftOut(_ cut: [String], of answer: String = "this result", leadIn: String = "") -> String? {
        guard !cut.isEmpty else { return nil }
        let notes = cut.map { adds[$0] ?? "what \($0) reads" }
        return leadIn + (leadIn.isEmpty ? "This" : "this") + " call's time ran out before \(listed(cut)) answered, so \(listed(notes)) \(cut.count == 1 ? "is" : "are") left out of \(answer)."
    }

    /// What each program's answer adds to a result, by the program's name; a program not here is said as "what it reads".
    static let adds = ["xccov": "the changed lines' coverage", "xcresulttool": "what the run's result bundle adds", "git": "what the branch changed"]

    static func listed(_ items: [String]) -> String {
        items.count == 1 ? items[0] : items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
    }

    /// Programs whose answer no result shows, so a cut one leaves nothing out of it: the pool's question of how many
    /// cores the Mac has, which falls back to one at a time.
    static let unshown: Set = ["sysctl"]

    private func note(_ argv: [String]) {
        let program = argv.first == "xcrun" ? argv.dropFirst().first : argv.first
        guard let name = program.map({ URL(fileURLWithPath: $0).lastPathComponent }), !Self.unshown.contains(name) else { return }
        cutCommands.withLock { if !$0.contains(name) { $0.append(name) } }
    }
}

extension Machine {
    /// What this machine's call left out, as `DeadlineRunner.leftOut` says it: nil when no deadline runs its commands,
    /// or it cut none.
    public func leftOut(of answer: String = "this result", leadIn: String = "") -> String? {
        (runner as? DeadlineRunner).flatMap { DeadlineRunner.leftOut($0.cut, of: answer, leadIn: leadIn) }
    }
}
