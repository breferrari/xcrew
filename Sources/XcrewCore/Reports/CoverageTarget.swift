import Foundation

/// A target in a run's coverage report, as `xcrun xccov view --report --json` gives it: its name, with its product's
/// extension in an app's report and without it in a package's, its product, how many of its lines can run and how many
/// ran, and its files by path (docs/findings.md, *Changed lines a
/// test run ran*). Read leniently: one odd target is skipped, not the whole report.
struct CoverageTarget: Sendable, Equatable, Decodable {
    struct File: Sendable, Equatable, Decodable {
        let path: String
    }

    let name: String
    let product: String?
    let covered: Int
    let executable: Int
    let files: [File]

    enum CodingKeys: String, CodingKey {
        case name, files
        case product = "buildProductPath"
        case covered = "coveredLines"
        case executable = "executableLines"
    }

    /// A test bundle's files are the tests themselves, not code a test runs. Its product is the bundle, whatever the
    /// target is named.
    var isTests: Bool { name.hasSuffix(".xctest") || product?.contains(".xctest/") == true }
    /// A target with lines that can run, none of which the run ran, as when a filter left its tests out.
    var isUnreached: Bool { !isTests && covered == 0 && executable > 0 }
    /// The module, without its product's extension: `Core` for `Core.framework`.
    var module: String { URL(filePath: name).deletingPathExtension().lastPathComponent }

    /// The targets in the report; none when it isn't that shape.
    static func targets(in json: String) -> [CoverageTarget] {
        struct Answer: Decodable { let targets: [Lenient<CoverageTarget>] }
        return (try? JSONDecoder().decode(Answer.self, from: Data(json.utf8)))?.targets.compactMap(\.wrappedValue) ?? []
    }
}
