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

    /// `test()`, or a test that takes arguments as the bundle lists it, with its labels: `parameterised(value:)`.
    public var function: String { name.hasSuffix(")") ? name : "\(name)()" }

    /// `Suite/test()`, as `xcresulttool` names one; an id it read with no `/`, as the case a crash under `System Failures`
    /// is filed as, by itself.
    public var xcresultID: String { name.isEmpty ? suite : "\(suite)/\(function)" }

}
