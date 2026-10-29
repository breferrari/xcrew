import Foundation
import XcrewCLI
import XcrewCore

let machine = Machine.live
let context = CheckContext(project: .current(machine: machine), machine: machine)
let standardInput = { isatty(STDIN_FILENO) == 1 ? Data() : await StandardInput.read(FileHandle.standardInput, within: .seconds(2)) }
exit(await CLI.run(Array(CommandLine.arguments.dropFirst()), context: context, standardInput: standardInput))
