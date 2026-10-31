import Foundation
@testable import XcrewCore
import XcrewTestSupport

/// MobileBuildMCP's real results, from the test bed's raw captures (`captures/raw/<name>.json`): the text Claude Code
/// hands the mod, and the JSON MobileBuildMCP returns beside it in `structuredContent`, which an older MobileBuildMCP or
/// a result Claude Code saved may give instead. A test reading them is skipped without a test bed.
enum Raw {
    static func capture(_ name: String) -> [String: Any] {
        let data = try! Data(contentsOf: Testbed.root.appending(path: "captures/raw/\(name).json"))
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    /// The result's text blocks, joined as the mod joins them.
    static func text(_ name: String) -> String {
        (capture(name)["content"] as! [[String: Any]]).compactMap { $0["text"] as? String }.joined()
    }

    static func json(_ name: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: capture(name)["structuredContent"]!, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    static func isError(_ name: String) -> Bool { capture(name)["isError"] as? Bool ?? false }

    static func output(_ name: String) -> ToolOutput {
        ToolOutput(text: text(name), server: .mobileBuildMCP, isError: isError(name))
    }

    static func jsonOutput(_ name: String) -> ToolOutput {
        ToolOutput(text: json(name), server: .mobileBuildMCP, isError: isError(name))
    }

    /// The result bundle `structuredContent` names, under `Captured.home`.
    static func bundle(_ name: String) -> String {
        let artifacts = ((capture(name)["structuredContent"] as! [String: Any])["data"] as! [String: Any])["artifacts"] as! [String: Any]
        return (artifacts["xcresultPath"] as! String).replacingOccurrences(of: "~", with: Captured.home)
    }
}
