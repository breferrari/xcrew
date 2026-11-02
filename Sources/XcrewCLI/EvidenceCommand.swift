import Foundation

import XcrewCore

/// A pull request's evidence for this branch (`EvidencePack`), from the ledger the mod sends.
struct EvidenceCommand: Command {
    let name = "evidence"
    let flags: Set<String> = []
    let usage = ["evidence   (mod) a pull request's evidence for this branch, from the mod's ledger as JSON on stdin"]

    static let nothing = "No evidence for this branch yet: no test has failed on it."

    func run(_ invocation: Invocation) async throws -> Int32 {
        guard let input = try? JSONDecoder().decode(EvidenceInput.self, from: await invocation.standardInput()) else {
            throw UsageError(description: "evidence reads the mod's ledger as JSON on stdin")
        }
        let context = CheckContext(project: invocation.context.project, machine: invocation.context.machine.pooled())
        let pack = await EvidencePack.make(input, project: context.project, machine: context.machine, open: { ResultBundle(path: $0, runner: context.runner) })
        let cut = (invocation.context.machine.runner as? DeadlineRunner).flatMap { DeadlineRunner.leftOut($0.cut, of: pack == nil ? "this answer" : "this block") }
        guard let pack else {
            // Nothing to say may be all the deadline let it find: then that's what it says.
            invocation.print(cut ?? Self.nothing)
            return 0
        }
        invocation.print(pack.block + (cut.map { "\n- " + $0 } ?? ""))
        if let attach = pack.attach { invocation.print("\n" + attach) }
        return 0
    }
}
