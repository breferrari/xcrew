import Foundation

import XcrewCore

/// The ledger's flaky marks after a repeated run: the mod sends the marks it keeps and the run's repeated tests, and keeps
/// what comes back, each mark with the passes it needs and whether it has them.
struct FlakyCommand: Command {
    let name = "flaky"
    let usage = ["flaky   (mod) the ledger's flaky marks after a repeated run, from the marks and the run's repeated tests as JSON on stdin"]

    struct Input: Decodable {
        let marks: [FlakyMark]
        let repeated: [ResultBundle.Repeated]
    }

    func run(_ invocation: Invocation) async throws -> Int32 {
        guard let input = try? JSONDecoder().decode(Input.self, from: await invocation.standardInput()) else {
            throw UsageError(description: "flaky reads the ledger's flaky marks and a run's repeated tests as JSON on stdin")
        }
        let marks = Dictionary(input.marks.map { ($0.test, $0) }, uniquingKeysWith: { first, _ in first })
        let after = input.repeated.compactMap { FlakyMark.after(marks[$0.test], $0) }
        invocation.print(String(decoding: try JSONEncoder.sorted.encode(after), as: UTF8.self))
        return 0
    }
}
