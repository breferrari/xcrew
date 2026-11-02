import Foundation

/// The test runs that are this branch's: those written while the checkout's HEAD was on it, as its HEAD reflog records
/// each checkout with its time, and since the branch's merge base (docs/findings.md, *The branch's test runs*). A run
/// another branch wrote in the same checkout could count a changed line as run that never was, so a run whose branch
/// can't be told is left out: with no reflog, only runs since the last commit count, and the choice says so.
enum BranchRuns {
    struct Chosen: Sendable, Equatable {
        /// The runs' result bundles, newest first.
        let paths: [String]
        /// No reflog could be read, so only runs since the branch's last commit count.
        let onlySinceLastCommit: Bool
    }

    /// The runs among `bundles` written on `branch`, newest first: within a span HEAD was on it and since `mergeBase`.
    /// `reflog` is `git reflog show HEAD --date=unix --format=%gd%x09%gs`, newest first; nil or empty when there's none.
    static func chosen(_ bundles: [(path: String, written: Date)], reflog: String?, branch: String?, mergeBase: Date?, lastCommit: Date?) -> Chosen {
        let newestFirst = bundles.sorted { $0.written > $1.written }
        guard let reflog, let branch, let spans = spans(reflog: reflog, branch: branch) else {
            let since = lastCommit ?? .distantFuture
            return Chosen(paths: newestFirst.filter { $0.written >= since }.map(\.path), onlySinceLastCommit: true)
        }
        let since = mergeBase ?? .distantPast
        let chosen = newestFirst.filter { bundle in
            bundle.written >= since && spans.contains { bundle.written >= $0.start && $0.end.map { bundle.written < $0 } ?? true }
        }
        return Chosen(paths: chosen.map(\.path), onlySinceLastCommit: false)
    }

    /// The spans HEAD was on `branch`, each from a checkout to it until the next checkout, the last open. Before the
    /// first checkout, HEAD was on the branch that checkout moved from, or on today's branch when none ever moved it.
    /// Nil for a reflog with no entry to read.
    static func spans(reflog: String, branch: String) -> [(start: Date, end: Date?)]? {
        let entries = reflog.split(separator: "\n").compactMap { line -> (at: Date, subject: Substring)? in
            guard let match = line.firstMatch(of: /^HEAD@\{(\d+)\}\t(.*)$/), let seconds = TimeInterval(match.output.1) else { return nil }
            return (Date(timeIntervalSince1970: seconds), match.output.2)
        }.reversed()
        guard let oldest = entries.first else { return nil }
        let moves = entries.compactMap { entry -> (at: Date, from: String, to: String)? in
            guard let move = entry.subject.firstMatch(of: /^checkout: moving from (.+) to (.+)$/) else { return nil }
            return (entry.at, String(move.output.1), String(move.output.2))
        }
        var on = moves.first?.from ?? branch
        var since = oldest.at
        var spans: [(start: Date, end: Date?)] = []
        for move in moves {
            if on == branch { spans.append((since, move.at)) }
            (on, since) = (move.to, move.at)
        }
        if on == branch { spans.append((since, nil)) }
        return spans
    }
}
