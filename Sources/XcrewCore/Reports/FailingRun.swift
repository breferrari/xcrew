import Foundation

/// A failing test run's failures, read against its result bundle's test list: each fact about them worked out here once.
/// It holds the bundle's id for each test the text names, the label on each failure line it adds, the bundle-only
/// failures it places in the text, and the run's failures in the order the run reported them.
/// It stays in the task that made it, as its test list does, and its facts grow as the report asks for them.
final class FailingRun {
    /// The run's test list, which every fact here is read from.
    let listing: TestList
    /// The bundle's id for a name the text gives, read from `listing`.
    let lookup: TestLookup
    /// The bundle's failed tests, nil when `listing` isn't one to read.
    let bundled: [ToolOutput.Failure]?
    /// The bundle's id for each failing test the text names, by the rule `TestLookup` keeps, for each failure line this
    /// run added to the text, and, once `ordering` has run, for each failed test it ordered.
    private(set) var resolutions: [TestID: TestLookup.Resolution] = [:]
    /// The label on each failure line this run added to the text.
    private(set) var labels: [TestID: String] = [:]

    /// A run whose facts are read from `listing`, its ids found by `lookup`, made from the same list.
    init(listing: TestList, lookup: TestLookup) {
        self.listing = listing
        self.lookup = lookup
        bundled = ResultBundle.failedTests(listing: listing)
    }

    /// `text` with each test it lists under more than one name folded into one entry, and the bundle's failed tests it
    /// doesn't list: a name's candidates where the name matches several of the
    /// bundle's tests, the rest after its failures, each labelled. Nil when nothing changes. It sets `resolutions` from
    /// the text, so it comes before `ordering`, which adds to them.
    func placing(in text: MobileText) -> MobileText? {
        var text = text
        var changed = false
        resolutions = Dictionary(text.lines.compactMap { $0.failing?.test }.map { ($0, lookup.resolution(of: $0)) }) { first, _ in first }
        // A test the text lists under more than one name, as a display-named test is, becomes one entry under its id.
        let resolvedFirst = resolutions
        if let folded = text.folding(by: { resolvedFirst[$0]?.found }) {
            (text, changed) = (folded, true)
            resolutions = Dictionary(text.lines.compactMap { $0.failing?.test }.map { ($0, lookup.resolution(of: $0)) }) { first, _ in first }
        }
        let named = Set(resolutions.values.compactMap(\.found)).union(resolutions.keys)
        let notNamed = (bundled ?? []).map { (TestID(xcresultID: $0.title), $0) }.filter { !named.contains($0.0) }
        let failed = Set(notNamed.map(\.0))
        let reported = resolutions.compactMapValues { resolution -> [TestID]? in
            if case let .ambiguous(ids) = resolution, ids.contains(where: failed.contains) { ids } else { nil }
        }
        let ambiguousIDs = Set(reported.values.joined())
        let resolved = resolutions
        let unlisted = Self.notListedByText(notNamed, in: text, exempt: ambiguousIDs) { resolved[$0]?.found == nil }
        let entries = unlisted.map { test, failure in (test: test, message: failure.message, id: lookup.resolution(of: test).found ?? test) }
        let cases = lookup.cases
        let listed = { (entry: (test: TestID, message: String, id: TestID)) -> MobileText.FailureLine in
            (test: entry.test, message: entry.message, place: ResultBundle.place(of: entry.id, in: cases))
        }
        let said = unlisted.isEmpty ? [] : text.lines.compactMap { line -> (TestID, String)? in
            if let test = MobileBuildMCPLine.passed(line.text) { return (test, "passed") }
            if case let .skipped(test?) = line.kind { return (test, "skipped") }
            return nil
        }
        let outcomes = Dictionary(said.map { (lookup.resolution(of: $0.0).found ?? $0.0, $0.1) }) { first, _ in first }
        labels = Dictionary(entries.compactMap { entry in outcomes[entry.id].map { (entry.test, Report.listedOtherwise($0)) } }) { first, _ in first }
        var placed: Set<TestID> = []
        for (name, ids) in reported.sorted(by: { $0.key.shown < $1.key.shown }) {
            let candidateIDs = Set(ids)
            let candidates = entries.filter { candidateIDs.contains($0.test) && !placed.contains($0.test) }
            for candidate in candidates { labels[candidate.test] = Report.reported(name, matching: ids) }
            guard let swapped = text.replacing(name, with: candidates.map(listed)) else { continue }
            (text, changed) = (swapped.text, true)
            placed.formUnion(candidates.map(\.test))
            if swapped.left == 0 { resolutions[name] = nil }
        }
        if let added = text.adding(unlisted: entries.filter { !placed.contains($0.test) }.map(listed)) { (text, changed) = (added, true) }
        for entry in entries { resolutions[entry.test] = .found(entry.id) }
        return changed ? text : nil
    }

    /// A run's failures in the order it reported them, and the note on those the text lists as failed that the bundle
    /// doesn't.
    typealias Ordered = (failures: [ToolOutput.Failure], note: String?)

    /// `failures`, the text's, in the order the run reported them with the bundle's failed tests (`Report.inRunOrder`),
    /// and the note on those the text lists as failed that the bundle doesn't; nil when the test list can't be read, and
    /// the text's stand. Each failed test the text names gets its id in `resolutions`.
    func ordering(_ failures: [ToolOutput.Failure]) -> Ordered? {
        guard let bundled else { return nil }
        for test in failures.filter(\.isTest).map({ TestID(xcresultID: $0.title) }) where resolutions[test] == nil { resolutions[test] = lookup.resolution(of: test) }
        let recorded = ResultBundle.results(in: listing.nodes)
        let results = recorded.merging(resolutions.compactMap { test, resolution in
            resolution.found.flatMap { recorded[$0] }.map { (test, $0) }
        }) { own, _ in own }
        let ordered = Report.inRunOrder(bundled, text: failures, cleared: ResultBundle.cleared(in: results), resolutions: resolutions)
        return (ordered.failures, Report.notFailedInBundleNote(ordered.disagreeing, results: results, ambiguous: Set(resolutions.filter(\.value.isAmbiguous).keys)))
    }

    /// Of `failures`, the bundle's, those `text` doesn't list, by message and place, `exempt` kept whatever the text lists:
    /// a failure the text lists under a name that matched none of the bundle's ids, as a display name, is still the
    /// text's, so it gets no line of its own. Only an entry whose name `unresolved` says matched no id counts, each for one
    /// failure. An entry's message is what follows its `Suite / name: `, and its place the first its lines name, a path or
    /// a file alone, up to the blank line that ends it. A failure with no place is never the text's. Two of the bundle's
    /// failures with one message at one place, matching one such entry, are told apart by nothing: the first in the
    /// bundle's list takes it.
    static func notListedByText(_ failures: [(TestID, ToolOutput.Failure)], in text: MobileText, exempt: Set<TestID>, unresolved: (TestID) -> Bool) -> [(TestID, ToolOutput.Failure)] {
        var listed: [String: Int] = [:]
        for (index, line) in text.lines.enumerated() {
            guard case let .entry(entry) = line.kind, entry.failing.map({ unresolved($0.test) }) ?? true,
                  let named = entry.text.range(of: " / "), let colon = entry.text[named.upperBound...].range(of: ": ") else { continue }
            let below = text.lines[(index + 1)...].prefix { line in
                if case .entry = line.kind { return false }
                return !line.isBlank
            }
            let place = below.lazy.compactMap { line in
                line.location.map { "\(ToolOutput.basename($0.path)):\($0.line)" }
                    ?? line.text.trimmingCharacters(in: .whitespaces).wholeMatch(of: /[^\s\/]+\.\w+:\d+/).map { String($0.output) }
            }.first
            if let place { listed["\(entry.text[colon.upperBound...])\n\(place)", default: 0] += 1 }
        }
        return failures.filter { test, failure in
            guard !exempt.contains(test), let place = failure.where else { return true }
            let key = "\(failure.message)\n\(place)"
            guard let count = listed[key], count > 0 else { return true }
            listed[key] = count - 1
            return false
        }
    }
}
