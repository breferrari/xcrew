import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// MobileBuildMCP's real results of the test bed's field scenarios (`captures/field/<name>.txt`), each its MCP result's
/// text as Claude Code hands it. A test reading them is skipped without a test bed, and one whose capture is missing
/// fails by name, naming the file.
enum Field {
    static func text(_ name: String) throws -> String {
        let url = Testbed.root.appending(path: "captures/field/\(name).txt")
        return try #require(try? String(contentsOf: url, encoding: .utf8), "the test bed has no captures/field/\(name).txt, at \(url.path)")
    }

    static func output(_ name: String, isError: Bool = false) throws -> ToolOutput {
        ToolOutput(text: try text(name), server: .mobileBuildMCP, isError: isError)
    }
}
