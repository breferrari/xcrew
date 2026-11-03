import Foundation

/// One test, however a server or `xcresulttool` spells it: `Suite/test`, `Suite/test()`, or
/// MobileBuildMCP's `Suite / test()`, which its line readers split.
public struct TestID: Sendable, Hashable {
    public let suite: String
    /// The test's name without its `()`.
    public let name: String

    public init(suite: some StringProtocol, name: some StringProtocol) {
        self.suite = String(suite)
        self.name = name.hasSuffix("()") ? String(name.dropLast(2)) : String(name)
    }

    /// A test from `xcresulttool`'s `Suite/test()`: split at the first `/`, the whole of it the suite when there's none.
    public init(xcresultID: some StringProtocol) {
        let parts = xcresultID.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        self.init(suite: parts.first ?? "", name: parts.count > 1 ? parts[1] : "")
    }

    /// `Suite/test`, as Xcrew shows a test.
    public var shown: String { "\(suite)/\(name)" }

    /// `Suite/test()`, as `xcresulttool` names one; an id it read with no `/`, as the case a crash under `System Failures`
    /// is filed as, by itself.
    public var xcresultID: String { name.isEmpty ? suite : "\(shown)()" }

    /// Whether `outer` is this test named from an outer suite, as a result bundle names a nested suite's test,
    /// `Outer/Suite/test`, that MobileBuildMCP's text names from its own, `Suite/test`.
    func isNested(in outer: TestID) -> Bool {
        outer.shown.hasSuffix("/\(shown)")
    }

    /// How a test the text names is found among the result bundle's ids.
    enum Resolution: Sendable, Equatable {
        /// The bundle's id for it: its own, the one nested id that ends with it, or the `System Failures` case its crash is
        /// filed under (`ResultBundle.resolution(of:among:crashCases:)`).
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

    /// This test among `ids`, the bundle's: its own id first; else a nested suite's test whose id ends with it, when
    /// exactly one does.
    func resolved(among ids: Set<TestID>) -> Resolution {
        if ids.contains(self) { return .found(self) }
        let nested = ids.filter(isNested).sorted { $0.shown < $1.shown }
        return nested.count == 1 ? .found(nested[0]) : nested.isEmpty ? .missing : .ambiguous(nested)
    }
}
