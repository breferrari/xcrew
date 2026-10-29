import Foundation
import XcrewCLI
import XcrewCore

let machine = Machine.live
let context = CheckContext(project: .current(machine: machine), machine: machine)
let standardInput = {
    guard isatty(STDIN_FILENO) != 1 else { return Data() }
    let input = await StandardInput.read(FileHandle.standardInput, idleFor: StandardInput.idleLimit)
    if !input.isComplete { FileHandle.standardError.write(Data(StandardInput.cutNote.utf8)) }
    return input.data
}
exit(await CLI.run(Array(CommandLine.arguments.dropFirst()), context: context, standardInput: standardInput))
