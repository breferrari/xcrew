/// The result bundle's test ids, and the one rule a test the run's text names is found among them by: its own id, else
/// the one nested suite's test whose id ends with it, else the `System Failures` case its crash is filed under. Built
/// once from a test list, so each name is found without reading every id again.
struct TestLookup: Sendable {
    let ids: Set<TestID>
    let crashCases: [TestID: TestID]
    /// Each id under its name and under every ending of it after a `/`, sorted: the ids a nested name can mean.
    private let byEnding: [String: [TestID]]

    /// `crashCases` as `ResultBundle.crashCases(in:)` reads them.
    init(ids: Set<TestID>, crashCases: [TestID: TestID] = [:]) {
        self.ids = ids
        self.crashCases = crashCases
        var byEnding: [String: [TestID]] = [:]
        for id in ids {
            let name = id.name
            byEnding[name, default: []].append(id)
            for slash in name.indices where name[slash] == "/" {
                byEnding[String(name[name.index(after: slash)...]), default: []].append(id)
            }
        }
        self.byEnding = byEnding.mapValues { $0.sorted { $0.shown < $1.shown } }
    }

    /// The test cases and the crash cases a test list's `nodes` hold.
    init(nodes: [[String: Any]]) {
        self.init(ids: Set(ResultBundle.testCases(in: nodes).keys), crashCases: ResultBundle.crashCases(in: nodes))
    }

    /// The bundle's id for `test`. A bundle id's suite holds no `/`, as `TestID.init(xcresultID:)` splits at the first,
    /// so a nested suite's path is in its name, and the text's `Inner/fails` is the end of `Outer/Inner/fails`'s.
    func resolution(of test: TestID) -> TestID.Resolution {
        if ids.contains(test) { return .found(test) }
        let nested = byEnding[test.shown] ?? []
        if nested.count == 1 { return .found(nested[0]) }
        if !nested.isEmpty { return .ambiguous(nested) }
        return crashCases[test].map { .found($0) } ?? .missing
    }
}
