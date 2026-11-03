import Foundation
import Testing
@testable import XcrewCore

/// A log is read line by line from its start until a line gives what's sought, wherever its pieces end.
@Suite struct TextFileTests {
    func file(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "xcrew-text-\(UUID().uuidString).log")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func found(_ text: String, _ sought: String) throws -> String? {
        let url = try file(text)
        defer { try? FileManager.default.removeItem(at: url) }
        return TextFile.firstLine(in: url) { line, previous in line.hasPrefix(sought) ? "\(previous ?? "none")|\(line)" : nil }
    }

    @Test func aLineLongerThanManyPiecesIsReadWholeAndTheNextFound() throws {
        let long = String(repeating: "x", count: TextFile.piece * 5 + 17)
        #expect(try found("\(long)\nwanted here\n", "wanted") == "\(long)|wanted here")
    }

    @Test func aLineAcrossAPiecesEndIsReadWhole() throws {
        let before = String(repeating: "a", count: TextFile.piece - 3)
        #expect(try found("\(before)\nwanted across the end\n", "wanted") == "\(before)|wanted across the end")
    }

    @Test func aLastLineWithoutANewlineIsRead() throws {
        #expect(try found("first\nwanted last", "wanted") == "first|wanted last")
    }

    @Test func aCharacterAcrossAPiecesEndIsReadWhole() throws {
        let before = String(repeating: "a", count: TextFile.piece - 1)
        #expect(try found("\(before)é\nwanted\n", "wanted") == "\(before)é|wanted")
    }

    @Test func aFileWithoutTheLineGivesNone() throws {
        #expect(try found("one\ntwo\n", "wanted") == nil)
    }
}
