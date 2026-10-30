import Foundation

/// What the mod knows of this folder and branch, for the evidence pack: the ledger's entries, as `hooks/mod/ledger.ts`
/// stores them, and the card's lines of usual run times.
public struct EvidenceInput: Sendable, Decodable {
    public struct Run: Sendable, Decodable {
        public let scope: String
        /// Milliseconds since 1970, as the mod's clock gives them.
        public let at: Double
        public let message: String?
        /// The run's result bundle; absent in entries the ledger recorded before it kept one.
        public let bundle: String?
    }

    public struct Flaky: Sendable, Decodable {
        public let failed: Int
        public let runs: Int
    }

    public struct Entry: Sendable, Decodable {
        public let test: String
        public let red: Run
        public let green: Run?
        public let flaky: Flaky?
    }

    public let ledger: [Entry]
    /// The card's run-time lines, as the mod formats them: `test_sim · App: usually 1m 20s, 312 tests`.
    public let times: [String]
}
