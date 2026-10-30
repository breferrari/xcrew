import Testing
@testable import XcrewCore

/// The imports a Swift file declares, read from its text: each form the grammar allows names its module, and nothing in
/// a comment or a string literal counts.
@Suite struct SwiftImportTests {
    @Test func eachFormNamesItsModuleAndLine() {
        let source = """
            import Core
            @testable import Data
            @_exported @preconcurrency import Feature
            public import Network
            internal import struct Payments.Card
            import Foundation.NSString
            @_implementationOnly
            import Hidden

            let value = 1
            """
        #expect(SwiftImport.all(in: source) == [
            SwiftImport(module: "Core", line: 1), SwiftImport(module: "Data", line: 2), SwiftImport(module: "Feature", line: 3),
            SwiftImport(module: "Network", line: 4), SwiftImport(module: "Payments", line: 5), SwiftImport(module: "Foundation", line: 6),
            SwiftImport(module: "Hidden", line: 8),
        ])
    }

    @Test func commentsAndStringsHoldNoImport() {
        let source = #"""
            // import Commented
            /* import Blocked
               /* nested */ import StillBlocked
            */
            let text = """
                import Quoted
                """
            let path = "/*"
            let raw = #"\(not interpolated) "# + "\("import Inner")"
            import Real
            """#
        #expect(SwiftImport.all(in: source) == [SwiftImport(module: "Real", line: 10)])
    }

    @Test func anImportInsideIfIsConditional() {
        let source = """
            import Core
            #if canImport(UIKit)
            import UIKit
            #if DEBUG
            import Debugging
            #endif
            #else
            import AppKit
            #endif
            import Data
            """
        #expect(SwiftImport.all(in: source) == [
            SwiftImport(module: "Core", line: 1), SwiftImport(module: "UIKit", line: 3, isConditional: true),
            SwiftImport(module: "Debugging", line: 5, isConditional: true), SwiftImport(module: "AppKit", line: 8, isConditional: true),
            SwiftImport(module: "Data", line: 10),
        ])
    }

    @Test func aWordThatOnlyStartsWithImportIsNoImport() {
        #expect(SwiftImport.all(in: "importer.run()\nlet imported = 1\nfunc importAll() {}\n") == [])
    }

    @Test func windowsLineEndingsSplitLines() {
        #expect(SwiftImport.all(in: "import Core\r\nimport Data\r\n") == [SwiftImport(module: "Core", line: 1), SwiftImport(module: "Data", line: 2)])
    }
}
