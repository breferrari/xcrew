import Foundation

/// A build's concurrency diagnostics in short, for the note after it: how many, and the note's words.
public struct ConcurrencySummary: Sendable, Equatable, Codable {
    public let count: Int
    public let note: String
}
