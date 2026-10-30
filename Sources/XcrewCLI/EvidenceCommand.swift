import Foundation

import XcrewCore

/// A pull request's evidence for this folder and branch (`EvidencePack`), from the ledger and run times the mod sends.
struct EvidenceCommand: Command {
    let name = "evidence"
    let flags: Set<String> = []
    let usage = ["evidence   (mod) a pull request's evidence for this branch, from the mod's ledger as JSON on stdin"]

    static let nothing = "No evidence for this branch yet: no test has failed on it, and no run here has been timed."

    func run(_ invocation: Invocation) async throws -> Int32 {
        guard let input = try? JSONDecoder().decode(EvidenceInput.self, from: await invocation.standardInput()) else {
            throw UsageError(description: "evidence reads the mod's ledger and run times as JSON on stdin")
        }
        let context = invocation.context
        guard let pack = await EvidencePack.make(input, project: context.project, machine: context.machine, open: { ResultBundle(path: $0, runner: context.runner) }) else {
            invocation.print(Self.nothing)
            return 0
        }
        invocation.print(pack.block)
        if let attach = pack.attach { invocation.print("\n" + attach) }
        return 0
    }
}
