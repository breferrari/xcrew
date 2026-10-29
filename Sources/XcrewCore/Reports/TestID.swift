import Foundation

/// One test, however a server or `xcresulttool` spells it: `Suite/test`, `Suite/test()`, or
/// MobileBuildMCP's `Suite / test()`.
public struct TestID: Sendable, Hashable {
    public let suite: String
    /// The test's name without its `()`.
    public let name: String

    public init(suite: some StringProtocol, name: some StringProtocol) {
        self.suite = String(suite)
        self.name = name.hasSuffix("()") ? String(name.dropLast(2)) : String(name)
    }

    /// A test from any of its spellings; nil for anything that isn't `Suite/test`.
    public init?(parsing text: some StringProtocol) {
        guard let slash = text.firstIndex(of: "/") else { return nil }
        let suite = text[..<slash].trimmingCharacters(in: .whitespaces)
        let name = text[text.index(after: slash)...].trimmingCharacters(in: .whitespaces)
        guard !suite.isEmpty, !name.isEmpty else { return nil }
        self.init(suite: suite, name: name)
    }

    /// `Suite/test`, as Xcrew shows a test.
    public var shown: String { "\(suite)/\(name)" }

    /// `Suite/test()`, as `xcresulttool` names one.
    public var xcresultID: String { "\(shown)()" }
}
