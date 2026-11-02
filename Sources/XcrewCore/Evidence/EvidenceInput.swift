import Foundation

/// What the mod knows of this branch, for the evidence pack: the ledger's entries, as `hooks/mod/ledger.ts` stores them.
/// Run times, which an older mod also sends, aren't read: a reviewer acts on test results, coverage and warnings.
public struct EvidenceInput: Sendable, Decodable {
    public struct Run: Sendable, Decodable {
        public let scope: String
        /// Milliseconds since 1970, as the mod's clock gives them.
        public let at: Double
        public let message: String?
        /// The run's result bundle; absent in entries the ledger recorded before it kept one.
        public let bundle: String?
    }

    /// A flaky mark: its counts, and with `xcrew flaky`'s answer, the passes in a row since its last failure, the passes
    /// needed and whether it has them; those are absent in a mark kept before.
    public struct Flaky: Sendable, Decodable {
        public let failed: Int
        public let runs: Int
        public let passes: Int?
        public let needed: Int?
        public let settled: Bool?
    }

    public struct Entry: Sendable, Decodable {
        public let test: String
        public let red: Run
        public let green: Run?
        public let flaky: Flaky?
        /// The newest run of the red's own scope, when its results didn't list the test, as for a test deleted since.
        public let unseen: Run?
    }

    public let ledger: [Entry]
}
