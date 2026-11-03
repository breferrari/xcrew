import Testing
@testable import XcrewCore

/// A value as one word of a shell command, and back.
@Suite struct ShellWordTests {
    /// A word quoted for a shell reads back as the value it quotes, a `'` inside it included; a plain one as it is.
    @Test(arguments: ["Suite/test", "Outer/Inner/fails()", "Suite/it's red", "/My App/Run.xcresult", "''", ""])
    func aQuotedWordReadsBackAsItsValue(value: String) {
        #expect(ShellWord.unquoted(ShellWord.word(value)) == value)
    }

    /// An empty value is a word of its own, not none.
    @Test func anEmptyValueIsQuoted() {
        #expect(ShellWord.word("") == "''")
    }
}
