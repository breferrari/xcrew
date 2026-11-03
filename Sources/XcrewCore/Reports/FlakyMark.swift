import Foundation

/// A test the ledger marks flaky: the repeated runs that saw it fail, folded together, and the passes in a row since its
/// last failure. It turns green only once those passes are enough that a test failing at the rate it was seen failing
/// would pass them all under 5% of the time (docs/findings.md, *Flaky or real*). The rate is measured, so from few runs
/// it can understate a rarer flake.
public struct FlakyMark: Sendable, Equatable, Codable {
    public let test: String
    /// The failures of every repeated run up to its last failure.
    public let failed: Int
    /// Those runs, the passes before the last failure included.
    public let runs: Int
    /// The passes in a row since the last failure, from repeated runs.
    public let passes: Int

    /// The chance below which passing every run at the seen rate counts as a fix.
    static let chance = 0.05

    /// What the passes needed are, said once where they're listed; the mod says it in the same words.
    public static let neededMeaning = "Passes needed: enough in a row that a test failing at the rate it was seen failing would pass them all under 5% of the time. From few runs, that rate can understate a rarer flake."

    public init(test: String, failed: Int, runs: Int, passes: Int) {
        self.test = test
        self.failed = failed
        self.runs = runs
        self.passes = passes
    }

    /// The passes in a row needed: the least `n` with `(1 − rate)ⁿ < 5%`, `n ≥ ln 0.05 / ln(1 − rate)`.
    public var needed: Int {
        guard runs > failed, failed > 0 else { return 1 }
        let rate = Double(failed) / Double(runs)
        return Int((log(Self.chance) / log(1 - rate)).rounded(.up))
    }

    public var isSettled: Bool { passes >= needed }

    /// The mark after a repeated run of its test: a failing run folds into the rate with the passes before it and resets
    /// them, a run passing every time adds its runs to the passes. Failing every run is a real failure, no longer flaky.
    /// A test never marked is marked only by a run that failed some of its runs.
    public static func after(_ mark: FlakyMark?, _ repeated: ResultBundle.Repeated) -> FlakyMark? {
        switch repeated.verdict {
        case .real: nil
        case .none: mark
        case .passed: mark.map { FlakyMark(test: $0.test, failed: $0.failed, runs: $0.runs, passes: $0.passes + repeated.runs) }
        case .flaky:
            FlakyMark(test: repeated.test, failed: (mark?.failed ?? 0) + repeated.failed, runs: (mark.map { $0.runs + $0.passes } ?? 0) + repeated.runs, passes: 0)
        }
    }

    enum CodingKeys: String, CodingKey {
        case test, failed, runs, passes, needed, settled
    }

    /// A mark the ledger kept before it counted passes has none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(test: container.decode(String.self, forKey: .test), failed: container.decode(Int.self, forKey: .failed),
                      runs: container.decode(Int.self, forKey: .runs), passes: container.decodeIfPresent(Int.self, forKey: .passes) ?? 0)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(test, forKey: .test)
        try container.encode(failed, forKey: .failed)
        try container.encode(runs, forKey: .runs)
        try container.encode(passes, forKey: .passes)
        try container.encode(needed, forKey: .needed)
        try container.encode(isSettled, forKey: .settled)
    }
}
