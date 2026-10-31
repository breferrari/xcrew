import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// MobileBuildMCP's real results, from the test bed's raw captures (`captures/raw/<name>.json`): the text Claude Code
/// hands the mod, and the JSON MobileBuildMCP returns beside it in `structuredContent`, which an older MobileBuildMCP or
/// a result Claude Code saved may give instead. A test reading them is skipped without a test bed, and one whose capture
/// is missing fails by name, naming the file.
enum Raw {
    /// The result bundle the `swift-testing` capture names, under `Captured.home`.
    static let passingBundle = "/Users/dev/Library/Developer/MobileBuildMCP/workspaces/field-3d32f8cd53a2/result-bundles/test_sim_2026-10-31T02-58-52-105Z_pid20279_8eddb088.xcresult"

    static func capture(_ name: String) throws -> [String: Any] {
        let url = Testbed.root.appending(path: "captures/raw/\(name).json")
        let data = try #require(try? Data(contentsOf: url), "the test bed has no captures/raw/\(name).json, at \(url.path)")
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any], "captures/raw/\(name).json isn't a JSON object")
    }

    /// A file beside the captures, as `xcresulttool`'s answer about a capture's bundle: `shapes.summary.json`.
    static func file(_ name: String) throws -> String {
        let url = Testbed.root.appending(path: "captures/raw/\(name)")
        return try #require(try? String(contentsOf: url, encoding: .utf8), "the test bed has no captures/raw/\(name), at \(url.path)")
    }

    /// The result's text blocks, joined as the mod joins them.
    static func text(_ name: String) throws -> String {
        let content = try #require(try capture(name)["content"] as? [[String: Any]], "captures/raw/\(name).json has no content")
        return content.compactMap { $0["text"] as? String }.joined()
    }

    static func json(_ name: String) throws -> String {
        let structured = try #require(try capture(name)["structuredContent"], "captures/raw/\(name).json has no structuredContent")
        return String(decoding: try JSONSerialization.data(withJSONObject: structured, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }

    static func isError(_ name: String) throws -> Bool { try capture(name)["isError"] as? Bool ?? false }

    static func output(_ name: String) throws -> ToolOutput {
        ToolOutput(text: try text(name), server: .mobileBuildMCP, isError: try isError(name))
    }

    static func jsonOutput(_ name: String) throws -> ToolOutput {
        ToolOutput(text: try json(name), server: .mobileBuildMCP, isError: try isError(name))
    }

    /// The result bundle `structuredContent` names, under `Captured.home`.
    static func bundle(_ name: String) throws -> String {
        let data = (try capture(name)["structuredContent"] as? [String: Any])?["data"] as? [String: Any]
        let path = try #require((data?["artifacts"] as? [String: Any])?["xcresultPath"] as? String, "captures/raw/\(name).json names no result bundle")
        return path.replacingOccurrences(of: "~", with: Captured.home)
    }
}
