import Foundation
import XcrewCLI
import XcrewCore

let machine = Machine.live
let context = CheckContext(project: .current(machine: machine), machine: machine) { FileHandle.standardError.write(Data(Progress.line($0).utf8)) }
let standardInput: @Sendable () async -> Data = {
    guard isatty(STDIN_FILENO) != 1 else { return Data() }
    let input = await StandardInput.read(FileHandle.standardInput, idleFor: StandardInput.idleLimit)
    if !input.isComplete { FileHandle.standardError.write(Data(StandardInput.cutNote.utf8)) }
    return input.data
}
let ended = await Interruption.run(on: [SIGTERM, SIGINT]) { await CLI.run(Array(CommandLine.arguments.dropFirst()), context: context, standardInput: standardInput) }
exit(ended.signal.map { 128 + $0 } ?? ended.value)
