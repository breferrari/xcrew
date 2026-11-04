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

    /// A test from `xcresulttool`'s `Suite/test()`, split at the first `/`. An id with no `/` is a top-level Swift
    /// Testing test, its function alone, `seededFailure()`, with no suite; or, as `xctest (<pid>) encountered an error`,
    /// the case a crash under `System Failures` is filed as, the whole of it the suite.
    public init(xcresultID: some StringProtocol) {
        let parts = xcresultID.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count > 1 {
            self.init(suite: parts[0], name: parts[1])
        } else if MobileBuildMCPLine.isProcessCrash(String(xcresultID)) {
            self.init(suite: xcresultID, name: "")
        } else {
            self.init(suite: "", name: xcresultID)
        }
    }

    /// What MobileBuildMCP names a test with no suite from, a top-level Swift Testing test's.
    static let unknownSuite = "(Unknown Suite)"

    /// `Suite/test`, as Xcrew shows a test; a test with no suite by its name alone.
    public var shown: String { suite.isEmpty ? name : "\(suite)/\(name)" }

    /// `test()`, or a test that takes arguments as the bundle lists it, with its labels: `parameterised(value:)`.
    public var function: String { name.hasSuffix(")") ? name : "\(name)()" }

    /// `Suite/test`, as `look` heads what it says of a test, and an id with no `/`, as a crash's case, by itself.
    var title: String { name.isEmpty ? suite : shown }

    /// The name `look` takes for it: a nested suite's test as the bundle names it, `()` and all, so its suite's `/` isn't
    /// read as a target's (`Target/Suite/test`); any other as `look` heads it.
    var lookName: String { name.contains("/") ? xcresultID : title }

    /// The `xcrew look` command on it in `bundle`, each a word a shell passes on as it is.
    func lookCommand(bundle: String) -> String { Self.lookCommand(naming: ShellWord.word(lookName), bundle: bundle) }

    /// The `xcrew look` command naming a test as `test` gives it, a word or a placeholder, in `bundle`.
    static func lookCommand(naming test: String, bundle: String) -> String { "xcrew look \(test) --bundle \(ShellWord.word(bundle))" }

    /// `Suite/test()`, as `xcresulttool` names one; a test with no suite by its function, and the case a crash under
    /// `System Failures` is filed as by itself.
    public var xcresultID: String { name.isEmpty ? suite : suite.isEmpty ? function : "\(suite)/\(function)" }

}
