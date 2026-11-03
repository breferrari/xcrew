import Foundation

/// A run's test list, `xcresulttool get test-results tests`, parsed once for every question a report or a look asks of
/// it: its JSON and its nodes, breadth first. It stays in the task that parsed it, as its JSON isn't `Sendable`.
struct TestList {
    let json: Any?
    let nodes: [[String: Any]]

    init(_ listing: String) {
        json = ResultBundle.parse(listing)
        nodes = ResultBundle.nodes(json)
    }

    /// Whether it's a test list at all, rather than what `xcresulttool` said when it couldn't read the bundle.
    var isListing: Bool { (json as? [String: Any])?["testNodes"] != nil }
}
