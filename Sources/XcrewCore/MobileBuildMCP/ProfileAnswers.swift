import Foundation

/// The answers that shape `.mobilebuildmcp/config.yaml`: the container to build and the
/// session-defaults profiles Claude switches between, `unit`, `app` and `ui`, each written only when
/// it has a scheme (see `ConfigRenderer.render`).
public struct ProfileAnswers: Sendable, Equatable {
    public var container: String
    public var testSimulator: String
    public var appSimulator: String
    public var appScheme: String?
    public var bundleID: String?
    public var uiTestScheme: String?
    public var testScheme: String?
    /// MobileBuildMCP's debugger backend, `dap` or `lldb-cli`, written at the config's top level when set.
    public var debuggerBackend: String?

    public init(
        container: String,
        testSimulator: String,
        appSimulator: String? = nil,
        appScheme: String? = nil,
        bundleID: String? = nil,
        uiTestScheme: String? = nil,
        testScheme: String? = nil
    ) {
        self.container = container.hasPrefix("./") ? String(container.dropFirst(2)) : container
        self.testSimulator = testSimulator
        self.appSimulator = appSimulator.nonEmpty ?? testSimulator
        self.appScheme = appScheme.nonEmpty
        self.bundleID = bundleID.nonEmpty
        self.uiTestScheme = uiTestScheme.nonEmpty
        self.testScheme = testScheme.nonEmpty
    }

    /// The profiles these answers write, each only with a scheme.
    public var profileNames: [String] {
        [("unit", testScheme), ("app", appScheme), ("ui", uiTestScheme)].compactMap { $0.1 == nil ? nil : $0.0 }
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}
