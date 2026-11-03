/// The result bundle's test cases, and the one rule a test the run's text names is found among them by: its own id,
/// else the one nested suite's test whose id ends with it, else the `System Failures` case its crash is filed under.
/// Built once from a test list, so each name is found without reading every id again.
struct TestLookup {
    /// The test list's cases under each test's id, as `ResultBundle.testCases(in:)` reads them.
    let cases: [TestID: [[String: Any]]]
    private let crashCases: [TestID: TestID]
    /// Each nested id under its name and every ending of it after a `/` that still holds one, sorted: the ids a name the
    /// text gives, always `Suite/test`, can mean.
    private let byEnding: [String: [TestID]]

    /// How a test the text names is found among the result bundle's ids.
    enum Resolution: Sendable, Equatable {
        /// The bundle's id for it: its own, the one nested id that ends with it, or the `System Failures` case its crash is
        /// filed under.
        case found(TestID)
        /// Two or more nested ids end with it, so none is taken.
        case ambiguous([TestID])
        case missing

        /// The bundle's id, when there's one.
        var found: TestID? {
            if case let .found(id) = self { id } else { nil }
        }

        /// Whether two or more nested ids end with the name, so none is taken.
        var isAmbiguous: Bool {
            if case .ambiguous = self { true } else { false }
        }
    }

    /// `crashCases` as `ResultBundle.crashCases(in:)` reads them.
    init(cases: [TestID: [[String: Any]]], crashCases: [TestID: TestID] = [:]) {
        self.cases = cases
        self.crashCases = crashCases
        var byEnding: [String: [TestID]] = [:]
        for id in cases.keys {
            var ending = Substring(id.name)
            while let slash = ending.firstIndex(of: "/") {
                byEnding[String(ending), default: []].append(id)
                ending = ending[ending.index(after: slash)...]
            }
        }
        self.byEnding = byEnding.mapValues { $0.sorted { $0.shown < $1.shown } }
    }

    /// Ids with no cases to read, as the failures a run order matches.
    init(ids: Set<TestID>) {
        self.init(cases: Dictionary(uniqueKeysWithValues: ids.map { ($0, []) }))
    }

    /// The test cases and the crash cases a test list's `nodes` hold.
    init(nodes: [[String: Any]]) {
        self.init(cases: ResultBundle.testCases(in: nodes), crashCases: ResultBundle.crashCases(in: nodes))
    }

    /// The bundle's id for `test`. A bundle id's suite holds no `/`, as `TestID.init(xcresultID:)` splits at the first,
    /// so a nested suite's path is in its name, and the text's `Inner/fails` is the end of `Outer/Inner/fails`'s.
    func resolution(of test: TestID) -> Resolution {
        if cases[test] != nil { return .found(test) }
        let nested = byEnding[test.shown] ?? []
        if nested.count == 1 { return .found(nested[0]) }
        if !nested.isEmpty { return .ambiguous(nested) }
        return crashCases[test].map { .found($0) } ?? .missing
    }
}
