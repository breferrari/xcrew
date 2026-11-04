import Foundation
import Synchronization
import XcrewCore

/// A runner that answers as `base` does and keeps every path it's asked about, so a golden's run can be held to the
/// folders it was given: a run that reaches the Mac's own files says what this Mac has, not what the code does.
struct GuardedRunner: CommandRunning {
    /// The paths the runner's commands named, shared by its copies.
    final class Reached: Sendable {
        let paths = Mutex<[String]>([])
    }

    let base: any CommandRunning
    let reached = Reached()

    func run(_ argv: [String], stdin: Data?) async -> CommandResult {
        reached.paths.withLock { $0 += argv.filter { $0.hasPrefix("/") } }
        return await base.run(argv, stdin: stdin)
    }

    func which(_ name: String) -> String? { base.which(name) }

    /// The paths its commands named outside `folders`, each spelled as the Mac may spell it.
    func outside(_ folders: [String]) -> [String] {
        let spellings = folders.flatMap { [$0, ProjectLayout.canonicalPath($0), $0.replacingOccurrences(of: "/private/var/", with: "/var/")] }
        return reached.paths.withLock { $0 }.filter { path in !spellings.contains { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") } }
    }
}
